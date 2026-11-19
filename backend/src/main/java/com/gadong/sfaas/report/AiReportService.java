package com.gadong.sfaas.report;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class AiReportService {
    private static final Pattern LINE_PATTERN = Pattern.compile("(?i)L\\s*(\\d+)");
    private static final String SYSTEM_PROMPT = """
            당신은 제조 현장의 생산계획 조정 보고서를 작성하는 전문가다.
            제공된 JSON 사실만 사용하고 값을 추측하지 않는다.
            수량 계산은 서버가 제공한 allocation을 그대로 사용한다.
            안전과 품질을 생산량보다 우선하며, 설비 자동 제어 명령은 내리지 않는다.
            한국어로 간결하게 작성하고 반드시 다음 JSON 형식만 반환한다.
            {"title":"...","summary":"...","actions":["..."],"risks":["..."],"markdown":"..."}
            """;

    private final AiReportProperties properties;
    private final ObjectMapper objectMapper;
    private final RestClient restClient;

    public AiReportService(AiReportProperties properties, ObjectMapper objectMapper, RestClient.Builder builder) {
        this.properties = properties;
        this.objectMapper = objectMapper;
        this.restClient = builder.baseUrl(properties.baseUrl()).build();
    }

    public AiReportResponse generate(AiReportRequest request) {
        int baseShortage = Math.max(0, Math.max(request.targetQty(), request.dueQty()) - request.completedQty());
        AiReportResponse.RequestInterpretation interpretation = interpretAdditionalRequest(request.additionalRequest());
        List<String> requestedStoppedLines = interpretation.stoppedLines();
        int stoppedPlanQty = request.lineConditions().stream()
                .filter(line -> !line.lineId().equalsIgnoreCase(request.lineId()))
                .filter(line -> requestedStoppedLines.contains(line.lineId().toUpperCase()))
                .mapToInt(AiReportRequest.LineCondition::currentPlan)
                .sum();
        int shortage = baseShortage + stoppedPlanQty;
        if (stoppedPlanQty > 0) {
            List<String> appliedRules = new ArrayList<>(interpretation.appliedRules());
            appliedRules.add("추가 정지 라인의 남은 계획 " + stoppedPlanQty + "개를 재배정 수량에 포함");
            interpretation = new AiReportResponse.RequestInterpretation(
                    interpretation.excludedLines(), interpretation.stoppedLines(), interpretation.priority(), appliedRules);
        }
        List<AiReportResponse.Allocation> allocations = allocate(
                shortage, request.lineId(), request.lineConditions(), new LinkedHashSet<>(interpretation.excludedLines()));
        Draft draft = properties.mock() ? mockDraft(request, shortage, allocations) : callLlm(request, shortage, allocations);

        return new AiReportResponse(
                UUID.randomUUID().toString(), request.downtimeId(), LocalDateTime.now(),
                properties.mock() ? "mock-template" : properties.model(), properties.mock(),
                shortage, draft.title(), draft.summary(), draft.actions(), allocations, draft.risks(), draft.markdown(), interpretation);
    }

    private AiReportResponse.RequestInterpretation interpretAdditionalRequest(String request) {
        if (request == null || request.isBlank()) {
            return new AiReportResponse.RequestInterpretation(
                    List.of(), List.of(), "BALANCED", List.of("기본 잔여 생산능력 기준 적용"));
        }

        Set<String> excludedLines = new LinkedHashSet<>();
        Set<String> stoppedLines = new LinkedHashSet<>();
        String normalized = request.replaceAll("\\s+", " ").trim();
        Matcher matcher = LINE_PATTERN.matcher(normalized);
        while (matcher.find()) {
            String lineId = "L" + matcher.group(1);
            int start = Math.max(0, matcher.start() - 40);
            int end = Math.min(normalized.length(), matcher.end() + 80);
            String context = normalized.substring(start, end);
            if (context.matches(".*(제외|빼|배정하지|사용하지|금지).*")) excludedLines.add(lineId);
            if (context.matches(".*(정지|중단|멈춰|멈춤|세워).*")) {
                stoppedLines.add(lineId);
                excludedLines.add(lineId);
            }
        }

        String priority = normalized.matches(".*(안전|품질).*우선.*") ? "SAFETY"
                : normalized.matches(".*(납기|긴급|마감).*우선.*") ? "DUE_DATE" : "BALANCED";
        List<String> rules = new ArrayList<>();
        stoppedLines.forEach(line -> rules.add(line + " 요청 정지 및 재배정 제외"));
        excludedLines.stream().filter(line -> !stoppedLines.contains(line))
                .forEach(line -> rules.add(line + " 재배정 제외"));
        if ("SAFETY".equals(priority)) rules.add("안전·품질 우선 검토");
        else if ("DUE_DATE".equals(priority)) rules.add("납기 준수 우선 검토");
        else rules.add("잔여 생산능력 기준 적용");
        return new AiReportResponse.RequestInterpretation(
                List.copyOf(excludedLines), List.copyOf(stoppedLines), priority, rules);
    }

    private List<AiReportResponse.Allocation> allocate(
            int shortage, String stoppedLine, List<AiReportRequest.LineCondition> conditions, Set<String> excludedLines) {
        List<AiReportRequest.LineCondition> candidates = conditions.stream()
                .filter(line -> !line.lineId().equals(stoppedLine))
                .filter(line -> !excludedLines.contains(line.lineId().toUpperCase()))
                .filter(line -> "RUNNING".equalsIgnoreCase(line.status()))
                .filter(line -> line.availableCapacity() > 0)
                .sorted(Comparator.comparing(AiReportRequest.LineCondition::lineId))
                .toList();

        int totalCapacity = candidates.stream().mapToInt(AiReportRequest.LineCondition::availableCapacity).sum();
        int assignableQty = Math.min(shortage, totalCapacity);
        if (assignableQty == 0 || totalCapacity == 0) return List.of();

        Map<String, Integer> quantities = new LinkedHashMap<>();
        List<AllocationShare> shares = new ArrayList<>();
        int floorTotal = 0;
        for (AiReportRequest.LineCondition line : candidates) {
            double exact = (double) assignableQty * line.availableCapacity() / totalCapacity;
            int floor = Math.min((int) Math.floor(exact), line.availableCapacity());
            quantities.put(line.lineId(), floor);
            shares.add(new AllocationShare(line, exact - floor));
            floorTotal += floor;
        }

        shares.sort(Comparator.comparingDouble(AllocationShare::remainder).reversed()
                .thenComparing(share -> share.line().lineId()));
        int remainder = assignableQty - floorTotal;
        while (remainder > 0) {
            boolean allocated = false;
            for (AllocationShare share : shares) {
                AiReportRequest.LineCondition line = share.line();
                int current = quantities.get(line.lineId());
                if (current >= line.availableCapacity()) continue;
                quantities.put(line.lineId(), current + 1);
                remainder--;
                allocated = true;
                if (remainder == 0) break;
            }
            if (!allocated) break;
        }

        return candidates.stream()
                .map(line -> new AiReportResponse.Allocation(
                        line.lineId(), quantities.get(line.lineId()),
                        "잔여 능력 비율 " + String.format("%.1f", line.availableCapacity() * 100.0 / totalCapacity)
                                + "%, 가용 " + line.availableCapacity() + "개, 기존 계획 " + line.currentPlan() + "개"
                                + (line.constraint() == null || line.constraint().isBlank() ? "" : ", 제약: " + line.constraint())))
                .toList();
    }

    private record AllocationShare(AiReportRequest.LineCondition line, double remainder) {
    }

    private Draft mockDraft(AiReportRequest request, int shortage, List<AiReportResponse.Allocation> allocations) {
        int assigned = allocations.stream().mapToInt(AiReportResponse.Allocation::quantity).sum();
        int unresolved = Math.max(0, shortage - assigned);
        String summary = request.equipmentName() + " 정지로 목표 대비 " + shortage
                + "개의 생산 부족이 예상됩니다. 정상 라인에 " + assigned + "개를 재배정하는 안을 제안합니다.";
        List<String> actions = new ArrayList<>();
        actions.add(request.equipmentName() + " 안전 정지 상태와 " + request.faultReason() + " 원인을 확인합니다.");
        allocations.forEach(a -> actions.add(a.lineId() + "라인에 " + a.quantity() + "개를 추가 배정합니다."));
        actions.add("계획 변경 전 생산관리자와 품질담당자의 승인을 받습니다.");

        List<String> risks = new ArrayList<>();
        risks.add("재배정 라인의 금형·자재·작업자 준비 상태를 확인해야 합니다.");
        if (unresolved > 0) risks.add("남은 " + unresolved + "개는 현재 가용 능력으로 해소할 수 없어 납기 협의가 필요합니다.");
        else risks.add("계산상 납기 수량 달성이 가능하지만 실제 복구시간에 따라 다시 계산해야 합니다.");

        String markdown = "# " + request.lineId() + "라인 생산계획 수정 제안\n\n"
                + "## 현황\n- 정지 설비: " + request.equipmentName() + "\n- 원인: " + request.faultReason()
                + "\n- 완료/목표: " + request.completedQty() + "/" + request.targetQty() + "개\n- 예상 부족: " + shortage + "개\n\n"
                + "## 제안\n" + actions.stream().map(v -> "- " + v).reduce("", (a, b) -> a + b + "\n")
                + "\n> 본 보고서는 의사결정 지원용 제안이며 설비나 생산계획을 자동 변경하지 않습니다.";
        return new Draft(request.lineId() + "라인 생산계획 수정 제안", summary, actions, risks, markdown);
    }

    private Draft callLlm(AiReportRequest request, int shortage, List<AiReportResponse.Allocation> allocations) {
        if (properties.apiKey() == null || properties.apiKey().isBlank()) {
            throw new IllegalStateException("AI_REPORT_API_KEY가 설정되지 않았습니다.");
        }
        try {
            Map<String, Object> facts = new LinkedHashMap<>();
            facts.put("incident", request);
            facts.put("calculatedShortage", shortage);
            facts.put("allocation", allocations);
            Map<String, Object> body = Map.of(
                    "model", properties.model(),
                    "temperature", 0.2,
                    "response_format", Map.of("type", "json_object"),
                    "messages", List.of(
                            Map.of("role", "system", "content", SYSTEM_PROMPT),
                            Map.of("role", "user", "content", objectMapper.writeValueAsString(facts))));

            String raw = restClient.post()
                    .uri("/chat/completions")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + properties.apiKey())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .body(String.class);
            JsonNode content = objectMapper.readTree(raw).path("choices").path(0).path("message").path("content");
            return objectMapper.readValue(content.asText(), Draft.class);
        } catch (Exception e) {
            throw new IllegalStateException("LLM 보고서 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.", e);
        }
    }

    private record Draft(String title, String summary, List<String> actions, List<String> risks, String markdown) {
    }
}
