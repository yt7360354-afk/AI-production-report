package com.gadong.sfaas.report;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;
import java.util.regex.MatchResult;
import java.util.regex.Pattern;

@Service
public class AiReportService {
    private static final Logger log = LoggerFactory.getLogger(AiReportService.class);
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    /** 라인 코드 A~F (명세서 lineId). 예: "A라인", "b 라인", "C line", "A, B라인", "A·C 라인" */
    private static final Pattern LINE_PATTERN = Pattern.compile(
            "(?i)(?<![A-Z0-9-])([A-F](?:\\s*[,·/와과및]\\s*[A-F])*)\\s*(?:라인|line)");
    private static final Pattern LINE_LETTER = Pattern.compile("(?i)[A-F]");
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
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        Duration timeout = Duration.ofSeconds(properties.timeoutSeconds() > 0 ? properties.timeoutSeconds() : 30);
        requestFactory.setConnectTimeout(timeout);
        requestFactory.setReadTimeout(timeout);
        this.restClient = builder.baseUrl(properties.baseUrl()).requestFactory(requestFactory).build();
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
        Draft draft;
        String fallbackReason = null;
        if (properties.mock()) {
            draft = mockDraft(request, shortage, allocations);
        } else {
            try {
                draft = callLlm(request, shortage, allocations);
            } catch (LlmUnavailableException e) {
                // 수량 계산은 이미 끝났으므로 문장만 템플릿으로 대신 만든다 (보고서 생성 자체는 실패시키지 않음)
                log.warn("LLM 보고서 생성 실패, 템플릿으로 대체합니다: {}", e.getMessage(), e.getCause());
                fallbackReason = e.getMessage();
                draft = mockDraft(request, shortage, allocations);
            }
        }
        boolean usedTemplate = properties.mock() || fallbackReason != null;

        return new AiReportResponse(
                UUID.randomUUID().toString(), request.downtimeId(), OffsetDateTime.now(KST).truncatedTo(ChronoUnit.SECONDS),
                usedTemplate ? "mock-template" : properties.model(), usedTemplate, fallbackReason,
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
        // 라인 언급마다 "그 언급부터 다음 라인 언급 전까지"만 보고 지시어를 찾는다.
        // 예: "A라인은 제외하고 F라인 정지" → A: 제외 / F: 정지 (앞 라인의 지시어가 뒤 라인에 섞이지 않게)
        List<MatchResult> mentions = LINE_PATTERN.matcher(normalized).results().toList();
        for (int i = 0; i < mentions.size(); i++) {
            MatchResult mention = mentions.get(i);
            int end = i + 1 < mentions.size() ? mentions.get(i + 1).start() : normalized.length();
            String context = normalized.substring(mention.end(), end);
            boolean exclude = context.matches(".*(제외|빼|배정하지|사용하지|금지).*");
            boolean stop = context.matches(".*(정지|중단|멈춰|멈춤|세워).*");
            for (String lineId : LINE_LETTER.matcher(mention.group(1)).results().map(r -> r.group().toUpperCase()).toList()) {
                if (exclude || stop) excludedLines.add(lineId);
                if (stop) stoppedLines.add(lineId);
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
                .filter(line -> isAllocatable(line.status()))
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

    /** 명세서 상태값(R/S/I/D/DC) 중 재배정 후보가 될 수 있는 상태인지 (설정 ai.report.allocatable-statuses) */
    private boolean isAllocatable(String status) {
        return status != null && properties.allocatableStatuses().stream().anyMatch(status.trim()::equalsIgnoreCase);
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
            throw new LlmUnavailableException("AI_REPORT_API_KEY가 설정되지 않았습니다", null);
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
            Draft draft = objectMapper.readValue(content.asText(), Draft.class);
            if (isBlank(draft.title()) || isBlank(draft.summary()) || draft.actions() == null || draft.risks() == null) {
                throw new LlmUnavailableException("LLM 응답 형식이 올바르지 않습니다", null);
            }
            return draft;
        } catch (LlmUnavailableException e) {
            throw e;
        } catch (Exception e) {
            // 키·응답 본문이 섞일 수 있어 원인 메시지는 로그에만 남기고 화면에는 일반 문구만 보낸다
            throw new LlmUnavailableException("LLM 호출에 실패했거나 " + properties.timeoutSeconds() + "초 안에 응답하지 않았습니다", e);
        }
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private record Draft(String title, String summary, List<String> actions, List<String> risks, String markdown) {
    }

    /** LLM 을 쓸 수 없을 때(키 없음·호출 실패·시간 초과·응답 형식 오류). 템플릿으로 대체하는 신호로만 쓴다. */
    static class LlmUnavailableException extends RuntimeException {
        LlmUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
