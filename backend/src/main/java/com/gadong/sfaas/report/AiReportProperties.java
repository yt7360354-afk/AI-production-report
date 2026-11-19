package com.gadong.sfaas.report;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

import java.util.List;

/**
 * AI 보고서 설정 (application.yml 의 ai.report.*).
 *
 * @param allocatableStatuses 재배정 후보로 쓸 라인 상태 (명세서 RSID). 기본 R·DC·I.
 *                            DC(통신 끊김)는 가동으로 계산하고, I(대기)는 재공이 없어 능력이 남는 상태라 포함한다.
 *                            D(고장)·S(계획정지)는 제외. I 포함 여부는 팀 확정 전까지 설정으로 바꿀 수 있다.
 */
@ConfigurationProperties(prefix = "ai.report")
public record AiReportProperties(
        boolean mock,
        String baseUrl,
        String apiKey,
        String model,
        @DefaultValue("30") int timeoutSeconds,
        @DefaultValue({"R", "DC", "I"}) List<String> allocatableStatuses
) {
}
