package com.gadong.sfaas.report;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "ai.report")
public record AiReportProperties(
        boolean mock,
        String baseUrl,
        String apiKey,
        String model,
        int timeoutSeconds
) {
}
