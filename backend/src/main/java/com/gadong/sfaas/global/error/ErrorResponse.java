package com.gadong.sfaas.global.error;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;

/**
 * API 명세서 v3 공통 오류 형식.
 * 예: { "status": 404, "code": "EQUIPMENT_NOT_FOUND", "message": "...", "timestamp": "2026-11-18T09:30:00+09:00" }
 */
public record ErrorResponse(int status, String code, String message, OffsetDateTime timestamp) {

    public static ErrorResponse of(int status, String code, String message) {
        return new ErrorResponse(status, code, message,
                OffsetDateTime.now(ZoneId.of("Asia/Seoul")).truncatedTo(ChronoUnit.SECONDS));
    }
}
