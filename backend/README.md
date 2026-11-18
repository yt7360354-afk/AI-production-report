# 🏭 SFaaS Back-End

라인 가동 현황 모니터링 시스템의 백엔드예요. (1조 가동가동해)

Node-RED가 MQTT로 보내는 설비 원시 값을 받아 **저장 · 판정(RSID 상태, 알람, 비가동 사유) · 집계**하고, 화면(Vue)에 REST와 WebSocket(STOMP)으로 제공해요.

## 📚 문서

| 문서 | 내용 |
|---|---|
| [API 명세서 v2](https://claude.ai/artifact/TFF4RzC1MZqwoATAQZYVmx) | REST API 41개, MQTT 토픽, WebSocket(STOMP) 채널, 공통 규칙. **개발 기준 문서** |
| Swagger UI | 서버 실행 후 http://localhost:8080/swagger-ui/index.html (코드에서 자동 생성) |

> API 주소·요청·응답 형식은 API 명세서 v2를 먼저 보고 구현해요. 명세와 다르게 만들어야 하면 명세서를 먼저 고쳐요.

## 🧰 기술

| 구분 | 사용 |
|---|---|
| 언어 / 프레임워크 | Java 17, Spring Boot 3.5 |
| 빌드 | Gradle (래퍼 포함, 따로 설치하지 않아요) |
| DB | PostgreSQL (`sfaas` DB, `sfaas_app` 계정), Spring Data JPA |
| 통신 | REST, WebSocket(STOMP), MQTT(Mosquitto) |
| 기타 | Spring Security, springdoc-openapi(Swagger), Lombok |

## ▶️ 처음 실행하기 (Windows)

1. **JDK 17 준비**: IntelliJ `File > Project Structure > SDK > Download JDK`에서 17(Eclipse Temurin)을 받아요. 없어도 첫 빌드 때 Gradle이 자동으로 내려받아요.
2. **PostgreSQL 준비**: `sfaas` DB를 만들고 `schema.sql` → `seed.sql` 순서로 실행해요. (개발환경 가이드 4장)
3. **로컬 설정 파일 만들기**: `src/main/resources/application-local.yml.example`을 복사해 같은 폴더에 `application-local.yml`을 만들고, 내 `sfaas_app` 비밀번호를 적어요. 이 파일은 Git에 올라가지 않아요.
4. **실행**

   ```bat
   gradlew.bat bootRun
   ```

5. **확인**: 콘솔에 `Started SfaasApplication`이 나오면 성공이에요.
   - Swagger UI: http://localhost:8080/swagger-ui/index.html

테스트는 PostgreSQL 없이도 돌아가요 (메모리 DB H2 사용).

```bat
gradlew.bat test
```

## 📁 패키지 구조

`src/main/java/com/gadong/sfaas/`

| 패키지 | 하는 일 | 담당 |
|---|---|---|
| `global` | 공통: 설정(Security, WebSocket, MQTT, Swagger), 예외 처리, 공통 응답 | 공용 |
| `auth` | 로그인, JWT, 사용자 관리 | BE2 |
| `master` | 기준정보: 라인, 설비, 공정, 비가동 코드, 관리값 기준 | BE1 |
| `ingest` | MQTT 수신(`sfaas/raw/#`) → 공정별 데이터 저장 | BE1 |
| `judge` | 판정: 공정 OK/NG, RSID 상태, 알람, 비가동 사유 | BE1 |
| `monitoring` | 모니터링 화면 API (현재 상태, 알람, 양품/불량 카운트) | BE1 |
| `availability` | 가동률 화면 API (가동률, 비가동 집계) | BE1 |
| `push` | WebSocket(STOMP)으로 화면에 밀어 주기 | BE1 |

각 패키지 안은 필요할 때 `controller / service / repository / entity / dto`로 나눠요.

값 하나가 지나가는 순서: `ingest`(수신) → `judge`(판정) → DB 저장 → `push`(화면 알림). 과거 기록 조회는 `monitoring`, `availability`의 REST API.

## 📏 지킬 규칙

- `spring.jpa.hibernate.ddl-auto`는 **validate**만 써요. 테이블은 `schema.sql`로만 만들고, 구조 변경은 DB 담당에게 먼저 말해요.
- 비밀번호·비밀키는 `application-local.yml`에만 적고 **커밋하지 않아요.**
- 사용자 비밀번호는 **BCrypt**로 암호화해 저장해요.
- 시간대는 **Asia/Seoul** 고정이에요.
- Controller와 MQTT 수신부에는 판정 로직을 넣지 않고 Service를 불러요. 판정 규칙은 `judge`에만 둬요.
- Entity를 그대로 응답하지 않고 DTO로 바꿔 내보내요.
- API 주소·응답 형식, MQTT 토픽, WebSocket 경로는 **[API 명세서 v2](https://claude.ai/artifact/TFF4RzC1MZqwoATAQZYVmx)**가 기준이에요. Base URL은 `/api/v1`.

## 🌿 브랜치

- `main`: 발표·시연이 가능한 상태. PR로만 합쳐요.
- `develop`: 개발 중인 코드를 모으는 곳.
- `feature/{작업-설명}`: 기능 하나. `develop`에서 만들고 PR로 `develop`에 합쳐요.

## 🚧 지금 상태

- 보안 설정은 **임시로 모든 요청 허용**이에요. JWT 로그인을 붙이면서 바꿔요. (`global/config/SecurityConfig.java`의 TODO)
- JWT 라이브러리, MQTT 수신 설정, Entity는 아직 없어요. 각 담당이 추가해요.
