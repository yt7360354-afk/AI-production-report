package com.gadong.sfaas.report;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * @param generatedAt    생성 시각 (ISO-8601 KST, +09:00)
 * @param mock           true 면 템플릿 문장 (시연 모드이거나 LLM 실패로 대체한 경우)
 * @param fallbackReason LLM 을 쓰려 했으나 실패해 템플릿으로 대체한 이유. 대체하지 않았으면 null
 */
public record AiReportResponse(
        String reportId,
        Long downtimeId,
        OffsetDateTime generatedAt,
        String model,
        boolean mock,
        String fallbackReason,
        int calculatedShortage,
        String title,
        String summary,
        List<String> actions,
        List<Allocation> allocations,
        List<String> risks,
        String markdown,
        RequestInterpretation requestInterpretation
) {
    public record Allocation(String lineId, int quantity, String reason) {
    }

    public record RequestInterpretation(
            List<String> excludedLines, List<String> stoppedLines, String priority, List<String> appliedRules) {
    }
}
