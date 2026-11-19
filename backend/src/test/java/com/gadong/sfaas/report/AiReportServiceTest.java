package com.gadong.sfaas.report;

import com.fasterxml.jackson.databind.json.JsonMapper;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

class AiReportServiceTest {

    private static final List<String> DEFAULT_STATUSES = List.of("R", "DC", "I");

    private static AiReportService service(boolean mock, String baseUrl, String apiKey, int timeoutSeconds) {
        AiReportProperties properties = new AiReportProperties(mock, baseUrl, apiKey, "test-model", timeoutSeconds, DEFAULT_STATUSES);
        return new AiReportService(properties, JsonMapper.builder().findAndAddModules().build(), RestClient.builder());
    }

    /** B라인 프레스 3호기 고장, 나머지 라인은 명세서 상태값으로 */
    private static AiReportRequest request(String additionalRequest) {
        return new AiReportRequest(
                5001L, "B", "B-PR3", "B라인 프레스 3호기", "압력 차(좌-우) 상한 초과 (13.4 / 상한 12.5)",
                OffsetDateTime.parse("2026-11-16T14:20:12+09:00"),
                200, 108, 200, "2026-11-16 24:00",
                List.of(
                        new AiReportRequest.LineCondition("A", "R", 1962, 69, ""),
                        new AiReportRequest.LineCondition("B", "D", 0, 92, "설비 고장"),
                        new AiReportRequest.LineCondition("C", "DC", 1958, 73, ""),
                        new AiReportRequest.LineCondition("D", "I", 1950, 81, ""),
                        new AiReportRequest.LineCondition("E", "S", 1961, 70, "계획정지"),
                        new AiReportRequest.LineCondition("F", "R", 1958, 73, "")),
                "", additionalRequest);
    }

    private static Map<String, Integer> allocationMap(AiReportResponse response) {
        return response.allocations().stream()
                .collect(Collectors.toMap(AiReportResponse.Allocation::lineId, AiReportResponse.Allocation::quantity));
    }

    @Test
    void 재배정_후보는_R_DC_I_상태만이고_고장_계획정지_라인은_제외된다() {
        AiReportResponse response = service(true, "http://localhost", "", 30).generate(request(""));

        assertThat(response.calculatedShortage()).isEqualTo(92);
        assertThat(allocationMap(response)).containsOnlyKeys("A", "C", "D", "F");
        assertThat(allocationMap(response).values().stream().mapToInt(Integer::intValue).sum()).isEqualTo(92);
    }

    @Test
    void 추가_요청의_A_F_라인_표기를_해석한다() {
        AiReportResponse response = service(true, "http://localhost", "", 30)
                .generate(request("A라인은 긴급 주문 생산 중이므로 제외하고 f 라인 정지, 납기 우선해줘"));

        AiReportResponse.RequestInterpretation interpretation = response.requestInterpretation();
        assertThat(interpretation.excludedLines()).containsExactlyInAnyOrder("A", "F");
        assertThat(interpretation.stoppedLines()).containsExactly("F");
        assertThat(interpretation.priority()).isEqualTo("DUE_DATE");
        assertThat(allocationMap(response)).containsOnlyKeys("C", "D");
        // F 정지로 F의 남은 계획 73개가 재배정 수량에 더해진다
        assertThat(response.calculatedShortage()).isEqualTo(92 + 73);
    }

    @Test
    void 앞_라인의_지시어가_뒤_라인에_섞이지_않는다() {
        AiReportResponse.RequestInterpretation interpretation = service(true, "http://localhost", "", 30)
                .generate(request("A라인은 제외하고 C라인은 그대로 생산해줘")).requestInterpretation();

        assertThat(interpretation.excludedLines()).containsExactly("A");
        assertThat(interpretation.stoppedLines()).isEmpty();
    }

    @Test
    void 여러_라인을_한번에_적어도_모두_해석한다() {
        AiReportResponse.RequestInterpretation interpretation = service(true, "http://localhost", "", 30)
                .generate(request("A, C라인은 재배정하지 말고 D·F 라인은 정지")).requestInterpretation();

        assertThat(interpretation.excludedLines()).containsExactlyInAnyOrder("A", "C", "D", "F");
        assertThat(interpretation.stoppedLines()).containsExactlyInAnyOrder("D", "F");
    }

    @Test
    void 장비_ID나_다른_영문은_라인으로_오해하지_않는다() {
        AiReportResponse response = service(true, "http://localhost", "", 30)
                .generate(request("B-PR3 PT1 도장 경로는 그대로 두고 제외할 라인은 없음"));

        assertThat(response.requestInterpretation().excludedLines()).isEmpty();
    }

    @Test
    void 생성_시각은_KST_오프셋으로_내려간다() {
        AiReportResponse response = service(true, "http://localhost", "", 30).generate(request(""));

        assertThat(response.generatedAt().getOffset().getTotalSeconds()).isEqualTo(9 * 3600);
        assertThat(response.mock()).isTrue();
        assertThat(response.fallbackReason()).isNull();
    }

    @Test
    void API_키가_없으면_템플릿으로_대체하고_이유를_알린다() {
        AiReportResponse response = service(false, "http://localhost", "", 30).generate(request(""));

        assertThat(response.mock()).isTrue();
        assertThat(response.model()).isEqualTo("mock-template");
        assertThat(response.fallbackReason()).contains("AI_REPORT_API_KEY");
        assertThat(response.title()).isEqualTo("B라인 생산계획 수정 제안");
    }

    @Test
    void LLM_호출이_실패하면_템플릿으로_대체한다() {
        // 9번 포트는 열려 있지 않아 연결이 바로 거부된다
        AiReportResponse response = service(false, "http://127.0.0.1:9/v1", "test-key", 2).generate(request(""));

        assertThat(response.mock()).isTrue();
        assertThat(response.fallbackReason()).contains("LLM 호출에 실패").doesNotContain("test-key");
        assertThat(response.allocations()).isNotEmpty();
    }
}
