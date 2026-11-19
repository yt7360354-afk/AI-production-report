# 리포트 기능 ↔ 팀 프론트·백엔드 연동 가이드

> 기준 문서: `SFaaS API 명세서 v3`(api-spec), `schema.sql v0.3.9`, `seed.sql v0.3.9` (2026-11-18)
> 대상 기능: 계획수정 보고서(`B-report.html`), 일일 생산 리포트(`B-daily.html`), AI 보고서 API(`report` 패키지)
> 작성: 2026-11-19 · 이 문서의 "제안" 항목은 명세서에 없는 내용이라 팀 확정이 필요합니다.

---

## 0. 한눈에 보기

| 구분 | 지금 (데모) | 연동 후 |
|---|---|---|
| 데이터 | 화면에 박힌 더미 값 (`A`, `archivedReports`, `reports`) | 명세서 API(M·U·G·R) + DB 조회 |
| 라인·설비 ID | `L1`~`L6`, `L2-PR3` | `A`~`F`, `B-PR3` (명세서·DB 기준) |
| 상태 값 | `RUNNING` / `STOPPED` | `R` / `S` / `I` / `D` / `DC` |
| 계획수정 보고서 생성 | 프론트가 모든 수치를 만들어 `POST /api/v1/ai-reports/generate`로 보냄 | 프론트는 **보고서 번호(또는 비가동 번호) + 추가 요청**만 보내고, 수치는 백엔드가 DB에서 만듦 |
| 계획수정 보고서 저장 | 없음 (새로고침하면 사라짐) | `reassignment_report` / `reassignment_detail` + 신규 `ai_report` |
| 일일 생산 리포트 | 서버 호출 없음 (더미) | 신규 일일 보고서 API + 신규 `daily_report` 테이블 |
| 인증 | 없음 (`permitAll`) | JWT (`Authorization: Bearer <token>`), 작성자 = 로그인 사용자 |
| 화면 기술 | 정적 HTML (`wireframes/후보`) | 팀 Vue 화면으로 옮기거나 정적 HTML 유지 (6장) |

**연동 핵심 3가지**
1. **ID·상태 값을 명세서 기준으로 바꾼다** (L1 → A, RUNNING → R …).
2. **수치는 백엔드가 DB에서 계산한다.** 지금처럼 프론트가 `lineConditions`를 만들어 보내면 화면 값을 조작해 다른 보고서를 만들 수 있고, 저장된 보고서를 다시 만들 수도 없습니다.
3. **생성한 보고서는 "생성 시점 스냅샷"으로 저장한다.** 원천 데이터가 나중에 바뀌어도 보고서는 그대로여야 합니다 (일일 보고서 문구 "생성 이후 원천 데이터 변경과 관계없이 작성 이력으로 보존").

---

## 1. 먼저 맞춰야 할 차이 (데모 ↔ 명세서 ↔ DB)

| # | 항목 | 데모 | 명세서 / DB | 할 일 |
|---|---|---|---|---|
| 1 | 라인 ID | `L1`~`L6` | `A`~`F` (`line.line_id`) | 화면·더미·백엔드 정규식(`L\s*(\d+)`) 모두 변경. 추가 요청 해석도 "A라인 제외", "B 정지" 형태로 |
| 2 | 설비 ID | `L2-PR3`, 이름 `L2 프레스 3단` | `B-PR3`, 이름 `B라인 프레스 3호기` (`equipment`) | 이름은 `equipment.equipment_name` 그대로 표시 |
| 3 | 라인 상태 | `RUNNING`, `STOPPED` | `R/S/I/D/DC` (M-02 `worstStatus`) | 재배정 후보: `R`, `DC`(가동으로 계산), `I`(재공 없음 → 능력 있음, **팀 확인**) / 제외: `D`, `S` |
| 4 | 라인 생산 능력 | "라인 CT 120초" (남은 34,529초 ÷ 120 = 287) | 가장 느린 공정 17초 → 시간당 약 211개 (`process.cycle_time_sec`) | `3600 ÷ max(cycle_time_sec of SLITTING·PRESS·WELDING)` 로 계산. 하드코딩 금지 |
| 5 | 부족(손실) 수량 | `max(목표, 납기수량) − 완료` (자정까지 못 만드는 수량) | R-01: **정지 시간 × 라인 생산 능력** | 두 정의가 다릅니다. 3.4절에서 결정 필요 |
| 6 | 납기 | `dueQty`, `dueAt` 입력 | DB에 납기·주문 테이블 없음 | 당분간 `production_target.target_qty` + 그날 24:00을 납기로 사용 |
| 7 | 생산계획 반영 버튼 | `생산계획 반영` (데모 처리) | **재배정 수행·승인 API 없음** (v3 결정). `approved*` 칸만 있음 | 버튼 숨기거나 "검토 완료" 표시로만. 승인 기능은 팀 결정 후 |
| 8 | 보고서 ID | UUID 문자열 | `reassignment_report.report_id` BIGSERIAL (숫자) | 화면 문서번호 `AI-RPT-YYYYMMDD-NNN`은 표시용으로 따로 생성 |
| 9 | 시간 형식 | `LocalDateTime` (오프셋 없음) | ISO-8601 KST `2026-11-18T09:30:00+09:00` | 응답은 `OffsetDateTime`(+09:00)으로 |
| 10 | 오류 응답 | Spring 기본 오류 | `{status, code, message, timestamp}` | `@RestControllerAdvice`로 공통 형식 |
| 11 | 근무조 | 주간 / 야간 | DB에 근무조 개념 없음 (`production_target`은 날짜 단위) | 4.3절 결정 필요 |

> ⚠️ **명세서 안의 모순**: 공통 규칙은 "프레스·용접 17초 → 시간당 약 211개"인데, R-01 설명에는 "프레스 3초 → 시간당 1,200개"가 남아 있습니다. R-01 문구를 211개 기준으로 고쳐야 합니다.

---

## 2. 전체 흐름

```
[설비] → MQTT → Node-RED → PostgreSQL ← Spring Boot(판정)
                                          │
        downtime_event (D, 진행 중) ──────┤  ① 정지 30분 이상 → 손실 수량 계산 → 여유 라인 추천
                                          │     → reassignment_report / reassignment_detail 자동 생성 (명세서 R)
                                          │
[계획수정 보고서 화면] ── ② 목록·상세 조회 (R-01, R-02, U-08, M-04)
        │
        └─ ③ "AI 보고서 생성" (신규 API) ── 백엔드가 DB로 스냅샷 조립 → 계산 → LLM(또는 템플릿)
                                          → ai_report 저장 → 응답
[일일 생산 리포트 화면] ── ④ "AI 일일 리포트 생성" (신규 API) ── 집계(M-07, U-01, G-01, U-08, M-13)
                                          → LLM(또는 템플릿) → daily_report 저장 → 응답
.doc / PDF 내려받기 ── 프론트에서 저장된 보고서 내용으로 템플릿 채움 (지금 방식 유지)
```

- 재배정 계산(①)은 명세서상 Spring Boot가 **자동**으로 합니다. AI 보고서(③)는 그 결과를 **설명하는 문서**를 사람이 요청할 때 만드는 것으로 나누면 명세서와 충돌하지 않습니다.
- 계산은 Java, 문장만 LLM (기존 원칙 유지). LLM에는 DB 전체나 개인정보를 보내지 않습니다.

---

## 3. 계획수정 보고서 연동

### 3.1 화면 요소별 데이터 출처

| 화면 위치 | 데모 값 | 연동 출처 (API) | DB |
|---|---|---|---|
| 왼쪽 "현재 트러블 슈팅" 카드 | 고정 1건 (`L2 프레스 3단`, `14:20:12 발생`) | **U-08** `GET /downtime/events?inProgress=true&status=D&minMinutes=30` (여러 건이면 카드 여러 개) | `downtime_event` (`ended_at IS NULL`, `status='D'`) |
| 카드 설명 "Pressure 1 상한 초과 · 장비고장(알람)" | 고정 | U-08 `detail`, `reasonCode` + **M-04** `GET /alarms/active?lineId=` (`itemName`, `measuredValue`, `upperLimit`) | `downtime_event.detail`, `downtime_code.code_name`, `alarm` |
| 카드 "보고서 미작성 / 작성 완료" 배지 | 화면 상태 | 신규 `ai_report` 존재 여부 (3.5절 응답의 `aiReport`) | `ai_report.downtime_id` |
| 실시간 반영 | 없음 | **W-01** `/topic/status`(D 전환) · **W-02** `/topic/alarms` 수신 시 U-08 다시 조회 | - |
| "이전에 작성한 보고서" 목록 | `archivedReports` 3건 | **R-01** `GET /reassignments?from&to&page&size` (+ AI 보고서가 있는 것만 표시하거나 배지) | `reassignment_report` ⨝ `ai_report` |
| 목록 클릭 → 상세 | `showArchivedReport()` | 신규 `GET /reassignments/{reportId}/ai-report` (저장된 스냅샷 그대로) | `ai_report.report_content`, `input_snapshot` |
| 문서번호 / 작성일시 | 생성 시 UUID 앞 6자리 | `ai_report.document_no`, `generated_at` | 신규 |
| 대상 라인 / 설비 / 발생 / 원인 | 고정 | 스냅샷: `equipment.line_id`, `equipment_name`, `downtime_event.started_at`, `detail` | |
| 생산 계획 / 현재 실적 / 예상 부족 | 200 / 108 / 92 | 스냅샷: `production_target.target_qty` / 그날 실적 / 계산 (3.4절) | |
| 정지 지속 | 11:56 (고정) | `now − downtime_event.started_at` (U-08 `minutes`) | |
| 2. 생산 영향 (남은 시간, 남은 라인 계획) | 9:35:29 / 92 | 계산 (3.4절) | |
| 3. 재배정 표 (남은 라인 계획·남은 능력·비율·추가 배정) | `A` 배열 | **R-02** `details[]` (`targetLineId`, `spareCapacity`, `addQty`) + 스냅샷의 라인별 남은 계획 | `reassignment_detail` |
| 4. 종합 검토 / 5. 권장 조치 / 6. 위험 | 생성 응답 | `ai_report.report_content` (LLM 또는 템플릿) | 신규 |
| AI 추가 요청 반영 결과 | 생성 응답 `requestInterpretation` | 그대로 (`ai_report`에 저장) | 신규 |
| 작성자 / 서명칸 "작성" | 김현수 (고정) | 로그인 사용자 (**C-01** 응답 `userName`, JWT) | `users.user_name`, `ai_report.generated_by` |
| 문서 상태 | 검토 대기 | `ai_report.status` (`DRAFT` → 표시 "검토 대기") | 신규 |

### 3.2 생성 요청 필드 ↔ DB 매핑 (백엔드가 조립)

지금 `AiReportRequest`의 필드를 **프론트가 아니라 백엔드가** DB에서 채웁니다.

| `AiReportRequest` 필드 | 출처 | 조회 예시 |
|---|---|---|
| `downtimeId` | 화면에서 받은 값 | `downtime_event.downtime_id` |
| `lineId` | 설비의 라인 | `SELECT line_id FROM equipment WHERE equipment_id = :eq` |
| `equipmentId`, `equipmentName` | `downtime_event.equipment_id` ⨝ `equipment` | |
| `faultReason` | 비가동 상세 + 진행 중 알람 | `downtime_event.detail` 또는 `alarm.message` + `measured_value`/`upper_limit` → `"좌 압력 상한 초과 (287.1 / 상한 285.3)"` |
| `faultStartedAt` | `downtime_event.started_at` | |
| `targetQty` | 그날 라인 목표 | `SELECT target_qty FROM production_target WHERE target_date = :d AND line_id = :line` |
| `completedQty` | 그날 라인 실적 (최종 양품) | `SELECT COUNT(*) FROM inspection_result WHERE line_id=:line AND result='OK' AND inspected_at >= :d AND inspected_at < :d + 1` |
| `dueQty`, `dueAt` | 납기 테이블 없음 | 당분간 `targetQty`, `:d 24:00` |
| `lineConditions[].lineId` | 6개 라인 | `SELECT line_id FROM line` |
| `lineConditions[].status` | 라인 대표 상태 | **M-02** `worstStatus` 와 같은 계산 (`equipment_status_history WHERE ended_at IS NULL`, 우선순위 D > DC > S > I > R) |
| `lineConditions[].currentPlan` | 라인 남은 계획 | `target_qty − 그날 실적` (0 미만이면 0) |
| `lineConditions[].availableCapacity` | 라인 여유 능력 | `floor(남은 초 × 시간당 능력 ÷ 3600) − currentPlan` (0 미만이면 0) |
| `lineConditions[].constraint` | 제약 문구 | 계획정지 중(S-01), 도장 경로(C-04 `currentPaintId`) 등. 없으면 빈 값 |
| `operatorNote` | 조치 메모 | `downtime_event.action_memo` (U-09로 입력) |
| `additionalRequest` | 화면 입력 | 그대로 |

> 라인 실적을 무엇으로 셀지(최종 양품 `inspection_result.OK` vs 용접 완료 수 `product_flow`) 팀 기준이 필요합니다. 검사기가 병목(7초, 6개 라인 공용)이라 검사 기준으로 세면 라인 실적이 늦게 잡힙니다. **라인 능력 계산(슬리팅~용접) 기준에 맞춰 "용접 OK 수"로 세는 것**을 권장합니다.

### 3.3 백엔드 코드 변경

| 파일 | 변경 |
|---|---|
| `AiReportController` | 기존 `POST /ai-reports/generate` 대신 3.5절 신규 API. 요청 본문은 `{ additionalRequest }`만 |
| 신규 `AiReportSnapshotService` | 3.2절 표대로 DB 조회해 `AiReportRequest`(스냅샷) 조립. JPA 엔티티 또는 `JdbcTemplate` |
| `AiReportService.allocate()` | `"RUNNING".equalsIgnoreCase(status)` → `Set.of("R","DC","I").contains(status)` (I 포함 여부는 팀 결정) |
| `AiReportService.interpretAdditionalRequest()` | 정규식 `L\s*(\d+)` → 라인 문자 `([A-F])\s*라인` |
| `AiReportService` | 생산 능력 `3600 / max(cycle_time_sec)` 를 `process` 테이블에서 읽기 |
| `AiReportService.callLlm()` | 타임아웃 적용(현재 `timeout-seconds` 미사용), 실패 시 `mockDraft()`로 대체 + `mock=true`로 표시 (가이드 원칙과 맞춤) |
| 신규 `AiReportRepository` | `ai_report` 저장·조회 |
| 응답 DTO | `generatedAt` → `OffsetDateTime`, `reportId` → `Long` + `documentNo` |
| 신규 `GlobalExceptionHandler` | 공통 오류 형식 `{status, code, message, timestamp}` (예: `DOWNTIME_NOT_FOUND`, `AI_REPORT_GENERATION_FAILED`) |
| `SecurityConfig` | `/api/v1/reassignments/**` 인증 필요 (팀 JWT 설정에 맞춤) |

### 3.4 계산식 (결정 필요)

**생산 능력 (명세서 기준)**
```
시간당 능력 = 3600 ÷ max(cycle_time_sec)  (SLITTING 16, PRESS 17, WELDING 17 → 17초)  ≈ 211개/h
```

**부족(손실) 수량 — 두 방식 중 택1**

| 방식 | 식 | 특징 |
|---|---|---|
| A. 명세서 R-01 | `손실 = 정지 시간(분) × 211 ÷ 60` | 지금까지 못 만든 양. 정지가 길어질수록 커짐. 보고서를 다시 만들면 값이 바뀜 |
| B. 데모 방식 | `부족 = max(0, 목표 − 실적)` (정지 라인이 오늘 다시 못 돈다고 가정) | 오늘 목표 기준. 복구 시각을 모르면 과대 추정 |
| C. 절충 (권장) | `부족 = min(목표 − 실적, 예상 정지 시간 × 211)` · 예상 정지 시간은 입력값(기본 = 남은 시간) | 복구 예상 시각을 사람이 넣으면 정확해짐 |

`reassignment_report.loss_qty`에는 명세서 정의(A)를 저장하고, AI 보고서에는 어떤 식을 썼는지 `input_snapshot`에 함께 남기세요.

**여유 능력 (재배정 표)**
```
남은 초           = (그날 24:00) − 생성 시각
라인 최대 생산     = floor(남은 초 × 211 ÷ 3600)
남은 라인 계획     = max(0, 목표 − 실적)
남은 능력(여유)    = max(0, 라인 최대 생산 − 남은 라인 계획)   → reassignment_detail.spare_capacity
추가 배정          = 부족 수량을 여유 능력 비율로 나눔 (현재 AiReportService.allocate 로직 그대로) → added_qty
```

### 3.5 신규 API 제안 (명세서 R 그룹에 추가)

| ID(제안) | 기능 | 메서드 | URL | 요청 | 응답 |
|---|---|---|---|---|---|
| R-04 | AI 보고서 생성 | POST | `/reassignments/{reportId}/ai-report` | `{ "additionalRequest": "A라인은 제외하고 납기 우선" }` | `201` 아래 예시 |
| R-05 | AI 보고서 조회 | GET | `/reassignments/{reportId}/ai-report` | - | 아래 예시 (없으면 404 `AI_REPORT_NOT_FOUND`) |
| R-06 | AI 보고서 내용 수정 (값 수정 저장) | PATCH | `/reassignments/{reportId}/ai-report` | `{ "content": { ...수정된 문장·표... } }` | 수정본 |

- 재배정 보고서(`reassignment_report`)가 아직 없는 진행 중 고장(30분 미만 등)에서도 만들 수 있게 하려면 `POST /downtime/events/{eventId}/ai-report` 도 둘 수 있습니다 (팀 결정).
- R-01 목록 응답에 `aiReport: { documentNo, status } | null` 을 추가하면 왼쪽 목록을 한 번에 그릴 수 있습니다.

```json
// R-04 응답 예시
{
  "aiReportId": 31,
  "reportId": 12,
  "downtimeId": 5001,
  "documentNo": "AI-RPT-20261118-031",
  "generatedAt": "2026-11-18T09:56:10+09:00",
  "generatedBy": { "userId": 3, "userName": "김현수" },
  "model": "gpt-4.1-mini",
  "mock": false,
  "status": "DRAFT",
  "snapshot": {
    "lineId": "B", "equipmentId": "B-PR3", "equipmentName": "B라인 프레스 3호기",
    "faultReason": "좌 압력 상한 초과 (287.1 / 상한 285.3)", "faultStartedAt": "2026-11-18T09:12:04+09:00",
    "targetQty": 1500, "completedQty": 1240, "capacityPerHour": 211, "remainingSec": 50880,
    "lines": [ { "lineId": "A", "status": "R", "currentPlan": 260, "availableCapacity": 2722 } ]
  },
  "calculatedShortage": 126,
  "allocations": [ { "lineId": "D", "quantity": 126, "reason": "잔여 능력 비율 ..." } ],
  "content": { "title": "...", "summary": "...", "actions": ["..."], "risks": ["..."] },
  "requestInterpretation": { "excludedLines": ["A"], "stoppedLines": [], "priority": "DUE_DATE", "appliedRules": ["A 재배정 제외", "납기 준수 우선 검토"] }
}
```

### 3.6 신규 테이블 제안 (`schema.sql`에 추가)

```sql
-- AI 계획수정 보고서: 재배정 계획서 1건에 대한 설명 문서 (생성 시점 스냅샷 보존)
CREATE TABLE ai_report (
    ai_report_id    BIGSERIAL    PRIMARY KEY,
    report_id       BIGINT       REFERENCES reassignment_report(report_id),   -- 재배정 계획서
    downtime_id     BIGINT       NOT NULL REFERENCES downtime_event(downtime_id),
    document_no     VARCHAR(30)  NOT NULL UNIQUE,     -- 'AI-RPT-20261118-031'
    generated_at    TIMESTAMP    NOT NULL DEFAULT now(),
    generated_by    INTEGER      REFERENCES users(user_id),
    model           VARCHAR(80)  NOT NULL,            -- 'mock-template' 또는 모델명
    prompt_version  VARCHAR(30)  NOT NULL,
    additional_request VARCHAR(500),
    input_snapshot  JSONB        NOT NULL,            -- 3.2절 조립 결과 + 사용한 계산식
    calculated_plan JSONB        NOT NULL,            -- 부족 수량·배정 결과
    report_content  JSONB        NOT NULL,            -- 제목·요약·조치·위험 (수정본 포함)
    status          VARCHAR(20)  NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'REVIEWED')),
    updated_at      TIMESTAMP
);
CREATE INDEX idx_ai_report_downtime ON ai_report (downtime_id);
```

- 승인(`approved*`)은 명세서 결정대로 `reassignment_report`의 칸을 비워 둡니다. AI 보고서의 `status`는 "검토 대기/검토 완료" 표시용입니다.

### 3.7 프론트 변경 (`B-report.html` 기준)

| 지금 코드 | 바꿀 내용 |
|---|---|
| `const A = [...]` (라인 더미) | 삭제. 표는 응답의 `snapshot.lines` + `allocations`로 그림 |
| `archivedReports` | 삭제. 목록은 R-01, 상세는 R-05 |
| `currentTrouble` 카드 (고정 HTML) | U-08(진행 중 D, 30분 이상) 결과로 카드 생성. 여러 건이면 여러 장 |
| `generateBtn` → `fetch('/api/v1/ai-reports/generate', 거대한 본문)` | `fetch('/api/v1/reassignments/{reportId}/ai-report', { body: { additionalRequest } })` + `Authorization` 헤더 |
| `editBtn` (값 수정) | 저장 시 R-06 호출 |
| `applyBtn` (생산계획 반영) | 명세서상 재배정 수행 없음 → 숨기거나 "검토 완료"(status `REVIEWED`)로 변경 |
| `docBtn` (.doc) | 그대로 사용 (화면 값으로 템플릿 채움) |
| 작성자 "김현수" | 로그인 사용자 이름 |
| `L1`~`L6` 표기 | `A`~`F` |

---

## 4. 일일 생산 리포트 연동

### 4.1 화면 섹션별 데이터 출처

| 화면 섹션 | 데모 값 | 연동 출처 (API) | 비고 |
|---|---|---|---|
| 문서번호 `DAILY-20261118-D` | 더미 | 신규 `daily_report.document_no` | `D` 주간 / `N` 야간 |
| 작성일시 · 작성자 · 문서 상태 | 더미 | `daily_report.generated_at`, 로그인 사용자, `status` | |
| 생산일자 · 근무조 | 더미 | 생성 요청 파라미터 | 근무조는 4.3절 |
| 요약: 생산계획 | 1,200 | **G-02** `GET /production/plans?from=d&to=d` 합계 | `production_target` |
| 요약: 양품 실적 · 불량 수량 | 1,164 / 31 | **M-07** `GET /production/counts?date=d` → `ok`, `processNg + ngVision` | |
| 요약: 달성률 | 97.0% | `ok ÷ 계획` | |
| 1. 생산 종합 현황 문장 | 템플릿 | 위 값으로 서버가 문장 생성 | |
| 2. 라인별 계획·실적·달성률 | 더미 | **G-01** `GET /production/summary?from=d&to=d&unit=day` (`planQty`, `actualQty`, `achievementRate`) | |
| 2. 라인별 불량 | 더미 | **M-07** `groupBy=line` → `byGroup[].ng` | |
| 2. 라인별 OEE | 더미 | ⚠️ 명세서에 라인별 OEE API 없음 (U-04는 `actual`, `stopCount`만) → **U-01** `?lineId=X` 6번 호출 또는 U-04에 `oee` 추가 요청 | |
| 3. 설비 종합 지표 (OEE·시간가동률·성능가동률·양품률) | 계산 더미 | **U-01** `GET /utilization/summary?from&to` → `oee`, `availability`, `performance`, `quality` | |
| 3. 공정별 생산·불량 | 더미 | **M-07** `byProcess` (`produced`, `ng`) | ⚠️ 명세서상 `lineId`를 지정해야 `byProcess`가 옴 → 전체용으로 확장 요청 또는 6개 라인 합산 |
| 4. 설비 비가동 및 계획수정 내역 | 1건 | **U-08** `GET /downtime/events?from&to&minMinutes=1` (또는 30) + 연결 보고서: **R-01**의 `downtimeId` 일치 건의 `documentNo` | 사유 이름은 `downtime_code.code_name` |
| 5. 마감 재공품(WIP) | 더미 | **M-13** `GET /production/wip` | ⚠️ M-13은 "지금" 값만 줌 → 마감 시점에 생성해 스냅샷으로 저장 |
| 5. AI 마감 검토 · 품질 요약 | 더미 문장 | LLM(또는 템플릿) 생성 → `daily_report.report_content` | |
| 6. 다음 근무조 인계사항 | 더미 | LLM 초안 + 사람이 수정 (값 수정 저장) | |
| 서명칸 (작성 / 생산관리 팀장) | 김현수 / 빈칸 | 작성 = 로그인 사용자, 팀장 칸은 출력 후 서명 | |

### 4.2 생성 방식

화면이 API 7~8개를 따로 불러 조립하는 대신, **백엔드가 한 번에 집계·저장하고 결과만 내려주는 것**을 권장합니다.

- 이유 1: 보고서는 "마감 시점 스냅샷"이라 나중에 다시 열어도 같은 값이어야 합니다.
- 이유 2: LLM 문장(AI 마감 검토·인계사항)이 같은 수치를 근거로 써야 합니다.
- 이유 3: 근무조 시간 범위·라인별 OEE처럼 명세서 API에 없는 집계를 서버에서 처리할 수 있습니다.

### 4.3 명세서·DB에 없어서 결정이 필요한 것

| 항목 | 현황 | 제안 |
|---|---|---|
| 근무조(주간/야간) | DB·명세서에 근무조 정의 없음. `production_target`은 날짜 단위 | ① 일 단위 보고서만 만든다 (가장 간단) ② `application.yml`에 근무조 시간 설정(예: 주간 08:00–20:00) + 목표는 일 목표를 시간 비율로 나눔 ③ `shift` 테이블 추가 |
| 라인별 OEE | U-04에 없음 | U-04 응답에 `oee`, `performance`, `quality` 추가 요청 |
| 전체 공정별 생산·불량 | M-07 `byProcess`는 `lineId` 지정 시만 | `lineId` 없이도 `byProcess` 내려주도록 요청 |
| 마감 WIP | M-13은 현재 값만 | 일일 보고서 생성 시 스냅샷 저장 (이력 API는 불필요) |
| 문서 상태(검토 대기/승인 완료) | 승인 API 없음 (재배정과 같은 원칙) | `DRAFT`/`REVIEWED` 표시만, 승인 기능은 보류 |

### 4.4 신규 API 제안 (일일 보고서, 그룹 D)

| ID(제안) | 기능 | 메서드 | URL | 요청 | 응답 |
|---|---|---|---|---|---|
| D-01 | 일일 보고서 목록 | GET | `/daily-reports` | 쿼리 `from, to, page, size` | `{ "content": [ { "dailyReportId": 9, "documentNo": "DAILY-20261117-D", "productionDate": "2026-11-17", "shift": "DAY", "status": "REVIEWED", "generatedAt": "2026-11-17T18:05:10+09:00" } ] }` |
| D-02 | 일일 보고서 상세 | GET | `/daily-reports/{id}` | - | 아래 예시 |
| D-03 | 일일 보고서 생성 (마감) | POST | `/daily-reports` | `{ "productionDate": "2026-11-18", "shift": "DAY" }` | `201` 상세와 같음. 같은 날·근무조가 이미 있으면 `409 DAILY_REPORT_EXISTS` |
| D-04 | 내용 수정 (인계사항 등) | PATCH | `/daily-reports/{id}` | `{ "content": { "handover": ["..."] } }` | 수정본 |

```json
// D-02 응답 예시 (화면 섹션과 1:1)
{
  "dailyReportId": 10, "documentNo": "DAILY-20261118-D", "productionDate": "2026-11-18", "shift": "DAY",
  "generatedAt": "2026-11-18T18:03:22+09:00", "generatedBy": { "userId": 3, "userName": "김현수" }, "status": "DRAFT",
  "summary": { "planQty": 1200, "okQty": 1164, "achievementRate": 97.0, "defectQty": 31 },
  "lines": [ { "lineId": "A", "planQty": 200, "actualQty": 198, "achievementRate": 99.0, "oee": 83.2, "ngQty": 5 } ],
  "metrics": { "oee": 78.4, "availability": 86.1, "performance": 93.5, "quality": 97.3 },
  "processes": [ { "process": "SLITTING", "produced": 1212, "ng": 4, "ngRate": 0.3 } ],
  "downtimes": [ { "eventId": 5001, "equipmentName": "B라인 프레스 3호기", "reasonName": "장비고장", "minutes": 220, "aiReportDocumentNo": null } ],
  "wip": [ { "process": "COIL", "nextProcess": "SLITTING", "wipQty": 31, "unit": "롤" } ],
  "content": { "summaryText": "...", "aiReview": "...", "qualitySummary": "...", "handover": ["...", "..."] },
  "model": "mock-template", "mock": true
}
```

> WIP 단위: 데모는 코일입고 재공을 "31롤"로 표시하지만, 명세서 M-13은 **제품 수**(롤 × 20)로 계산합니다(`coil_receipt.product_qty`). 화면 단위를 "개"로 통일하거나 롤 수를 따로 내려야 합니다.

### 4.5 신규 테이블 제안

```sql
-- 일일 생산 마감 보고서 (생성 시점 스냅샷 보존)
CREATE TABLE daily_report (
    daily_report_id  BIGSERIAL    PRIMARY KEY,
    document_no      VARCHAR(30)  NOT NULL UNIQUE,     -- 'DAILY-20261118-D'
    production_date  DATE         NOT NULL,
    shift            VARCHAR(10)  NOT NULL DEFAULT 'DAY' CHECK (shift IN ('DAY', 'NIGHT', 'ALL')),
    generated_at     TIMESTAMP    NOT NULL DEFAULT now(),
    generated_by     INTEGER      REFERENCES users(user_id),
    model            VARCHAR(80)  NOT NULL,
    data_snapshot    JSONB        NOT NULL,            -- summary·lines·metrics·processes·downtimes·wip
    report_content   JSONB        NOT NULL,            -- 문장·인계사항 (수정본 포함)
    status           VARCHAR(20)  NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'REVIEWED')),
    updated_at       TIMESTAMP,
    UNIQUE (production_date, shift)
);
```

### 4.6 프론트 변경 (`B-daily.html` 기준)

| 지금 코드 | 바꿀 내용 |
|---|---|
| `const reports = { today, '1117', ... }` | 삭제. 목록은 D-01, 상세는 D-02 |
| 왼쪽 "오늘 마감" 카드 | 오늘 날짜·근무조로 D-01 조회 → 없으면 "보고서 미작성", 있으면 "작성 완료" |
| `generateDaily` 클릭 | D-03 호출 후 응답으로 `showReport()` |
| `showReport(r)` | 입력을 D-02 응답 구조로 변경 (`r.lines[i].lineId` 등). 그리는 코드는 거의 그대로 |
| 공정 이름 `슬리팅`/`출고 비전` | 응답의 `process` 코드 → 표시명은 `process.process_name` |
| `docDaily` (.doc) | 그대로 (화면 값으로 `daily-report-template.doc` 채움) |

---

## 5. 공통 연동 규칙

| 항목 | 규칙 (명세서 공통 규칙) | 적용 |
|---|---|---|
| Base URL | `http://localhost:8080/api/v1` | 프론트는 `/api/v1/...` 상대 경로 + Vite 프록시(`/api → 8080`) 유지 |
| 인증 | C-01 로그인 → `Authorization: Bearer <accessToken>` | `fetch` 공통 함수에 헤더 추가. 401이면 로그인 화면으로 |
| 시간 | ISO-8601 KST `+09:00`, 백엔드 `Asia/Seoul` | 응답 `OffsetDateTime`. 화면은 `toLocaleString('ko-KR')` |
| 응답 | 래퍼 없음, 목록은 `page`, `size` | R-01/D-01 목록에 `content`, `totalElements` |
| 오류 | `{status, code, message, timestamp}` | 화면은 `message`를 그대로 표시 ("생성 실패" 대신) |
| 명명 | URL 소문자·복수형, JSON camelCase | `ai-report`, `daily-reports` |
| 실시간 | STOMP `/ws` | W-01·W-02 수신 시 "현재 트러블" 목록 다시 조회 |
| LLM 키 | 서버 환경 변수만 (`AI_REPORT_*`) | 프론트·Git에 넣지 않음 |

---

## 6. 팀 저장소로 합치는 방법

### 백엔드 (`com.gadong.sfaas`)
- 패키지가 이미 같습니다. `report` 패키지를 팀 백엔드에 그대로 넣고, 3.3절대로 DB 조회 부분을 추가합니다.
- 팀 백엔드는 JPA `ddl-auto=validate`라서 **`schema.sql`에 `ai_report`, `daily_report`를 먼저 추가**해야 기동됩니다.
- 담당 구분상 집계 API(M·U·G·R)는 BE1 영역이므로, 일일 보고서 집계는 BE1 서비스(가동률·생산량 계산)를 **재사용**하고 새로 계산하지 않습니다.
- `build.gradle`: 팀 쪽에 web·validation·jpa가 이미 있으므로 추가 의존성 없음 (`RestClient`는 Spring 6.1 기본 제공).

### 프론트 (Vue)
| 방식 | 장점 | 단점 |
|---|---|---|
| A. Vue 페이지로 옮김 (`src/pages/Report*.vue`) **권장** | 팀 라우팅·로그인·헤더 공유, 상태 관리 일관 | 옮기는 작업 필요 (HTML 구조·CSS는 그대로 가져와도 됨) |
| B. 정적 HTML 유지 (`public/report/…`) | 지금 코드 그대로 | 로그인 토큰·헤더·메뉴를 따로 처리해야 함 |

- 공통으로 옮길 것: `public/templates/*.doc` (그대로), `.doc` 채우기 코드 → `src/utils/docTemplate.ts` 같은 모듈로 분리.
- 팀 `vite.config.ts`에 `/api` 프록시가 있는지 확인 (현재 팀 저장소에는 미커밋 상태였음).

---

## 7. 작업 순서 (체크리스트)

**1단계 — 기준 맞추기 (데이터 없이도 가능)** ✅ 2026-11-19 완료
- [x] 라인·설비 ID를 A~F / `B-PR3` 형식으로 변경 (화면·더미·백엔드 정규식, `.doc` 템플릿 고정 문구)
  - 추가 요청 해석: "A라인", "A, C라인", "D·F 라인" 인식. 지시어는 그 라인 언급부터 다음 라인 언급 전까지만 적용
- [x] 상태 값 `R/S/I/D/DC` 반영. 재배정 후보는 설정 `ai.report.allocatable-statuses` (기본 `R,DC,I`, **I 포함은 팀 확정 필요**)
- [~] 생산 능력: 17초(시간당 약 211개) 기준으로 계산. 이 저장소에는 DB가 없어 화면의 `LINE_CYCLE_SEC = 17` 한 곳에 두었고, 2단계에서 `process.cycle_time_sec` 조회로 바꿈
- [x] 응답 시간 `+09:00` (`OffsetDateTime`), 요청 `faultStartedAt`도 `+09:00`. 공통 오류 형식 `{status, code, message, timestamp}` (`GlobalExceptionHandler`)
- [x] LLM 타임아웃(`AI_REPORT_TIMEOUT_SECONDS`) 적용, 실패·키 없음·응답 형식 오류 시 템플릿으로 대체하고 `fallbackReason`으로 이유 표시
- 함께 고친 것: 이전 보고서 화면에서 발생 현황·정지 지속·남은 시간이 바뀌지 않던 문제, `.doc`에 설비·원인·시간이 고정 값으로 들어가던 문제, 재배정 표 비율에 제외 라인이 포함되던 문제

**2단계 — 계획수정 보고서 (P1 R-01·R-02, U-08, M-04 완성 후)**
- [ ] `ai_report` 테이블 추가 (`schema.sql`)
- [ ] 스냅샷 조립 서비스 (3.2절)
- [ ] R-04/R-05/R-06 구현, R-01에 `aiReport` 요약 추가
- [ ] 화면: 현재 트러블 = U-08, 목록 = R-01, 생성 = R-04, 작성자 = 로그인 사용자
- [ ] W-01/W-02 수신 시 트러블 목록 갱신

**3단계 — 일일 생산 리포트 (P2 G-01·G-02, U-01, M-07, M-13 완성 후)**
- [ ] 근무조 정책 확정 (4.3절)
- [ ] `daily_report` 테이블 추가
- [ ] D-01~D-04 구현 (집계는 BE1 서비스 재사용)
- [ ] 화면: 목록 = D-01, 생성 = D-03, 상세 = D-02

**4단계 — 마무리**
- [ ] JWT 인증 적용, 권한(작성 가능 역할) 확정
- [ ] Vue 페이지로 이전 (6장)
- [ ] 명세서에 R-04~R-06, D-01~D-04 추가, R-01 "프레스 3초 → 1,200개" 문구 수정

---

## 8. 팀에 확인할 결정 사항

1. 부족(손실) 수량 정의: 명세서(정지 시간 × 211) / 데모(목표 − 실적) / 절충안 중 무엇으로 보고서를 쓸지 (3.4절)
2. 라인 실적 기준: 최종 양품(검사 OK) vs 용접 완료 수 (3.2절)
3. 재배정 후보에 `I`(대기) 라인을 넣을지
4. AI 보고서를 재배정 계획서(30분 이상)에만 만들지, 진행 중 고장 전체에 만들지
5. "생산계획 반영" 버튼 처리 (명세서상 재배정 수행 없음)
6. 근무조(주간/야간) 정의 방식 (4.3절)
7. 라인별 OEE·전체 공정별 생산량을 기존 API(U-04, M-07)에 추가할지
8. 보고서 상태값(`DRAFT`/`REVIEWED`)과 승인 기능 보류 여부
9. 납기 데이터가 생길 때까지 "그날 24:00 = 납기"로 둘지
10. 신규 API ID(R-04~R-06, D-01~D-04)와 담당(BE1/BE2) 배정
