package com.gadong.sfaas.global.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Swagger UI: http://localhost:8080/swagger-ui/index.html */
@Configuration
public class OpenApiConfig {

    @Bean
    OpenAPI sfaasOpenApi() {
        return new OpenAPI()
                .info(new Info()
                        .title("SFaaS 라인 가동 현황 모니터링 API")
                        .version("v1")
                        .description("REST API 문서. MQTT·WebSocket 규칙은 API 명세서 v2가 기준이에요."));
    }
}
