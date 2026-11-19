package com.gadong.sfaas.report;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.time.OffsetDateTime;
import java.util.List;

public record AiReportRequest(
        @NotNull Long downtimeId,
        @NotBlank String lineId,
        @NotBlank String equipmentId,
        @NotBlank String equipmentName,
        @NotBlank String faultReason,
        @NotNull OffsetDateTime faultStartedAt,
        @Min(0) int targetQty,
        @Min(0) int completedQty,
        @Min(0) int dueQty,
        @NotBlank String dueAt,
        @NotEmpty List<@Valid LineCondition> lineConditions,
        String operatorNote,
        String additionalRequest
) {
    public record LineCondition(
            @NotBlank String lineId,
            @NotBlank String status,
            @Min(0) int availableCapacity,
            @Min(0) int currentPlan,
            String constraint
    ) {
    }
}
