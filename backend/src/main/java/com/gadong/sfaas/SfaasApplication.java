package com.gadong.sfaas;

import jakarta.annotation.PostConstruct;
import java.util.TimeZone;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class SfaasApplication {

    public static void main(String[] args) {
        SpringApplication.run(SfaasApplication.class, args);
    }

    /** 시간대는 Asia/Seoul로 고정해요. (11/16 팀 결정) */
    @PostConstruct
    void setTimeZone() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Seoul"));
    }
}
