package com.gadong.sfaas.report;

import java.time.LocalDateTime;
import java.util.List;

public record AiReportResponse(
        String reportId,
        LocalDateTime generatedAt,
        String model,
        boolean mock,
        String title,
        String summary,
        List<String> actions,
        List<Allocation> allocations,
        List<String> risks,
        String markdown
) {
    public record Allocation(String lineId, int quantity, String reason) {
    }
}
