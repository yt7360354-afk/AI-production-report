package com.gadong.sfaas.report;

import java.time.LocalDateTime;
import java.util.List;

public record AiReportResponse(
        String reportId,
        Long downtimeId,
        LocalDateTime generatedAt,
        String model,
        boolean mock,
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
