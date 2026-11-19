# AI 생산계획 수정 보고서 구현 가이드

## 구현된 데모 흐름

1. 사용자가 계획수정 보고서 화면(`B-report.html`)에서 조건을 확인하고 생성 버튼을 누른다.
2. 프론트가 `POST /api/v1/ai-reports/generate`를 호출한다.
3. 백엔드가 목표·납기·실적을 기준으로 부족 수량을 계산한다.
4. 백엔드가 정상 라인의 가용 능력 안에서 추가 수량을 배정한다.
5. mock 모드에서는 템플릿으로, 운영 모드에서는 LLM으로 보고서 문장을 만든다.
6. 결과는 제안으로만 표시하며 생산계획이나 설비를 자동 변경하지 않는다.

## 실행

백엔드는 Java 17 또는 21을 사용한다.

```powershell
cd backend
.\gradlew.bat bootRun
```

```powershell
cd frontend
npm install
npm run dev
```

또는 저장소 루트에서 `.\run-report.ps1` 로 둘 다 실행한다.

기본값 `AI_REPORT_MOCK=true`에서는 API 키가 없어도 동작한다.

실제 LLM을 사용할 때 서버 환경 변수에만 키를 둔다. 키를 프론트 코드나 Git에 넣지 않는다.

```text
AI_REPORT_MOCK=false
AI_REPORT_BASE_URL=https://api.openai.com/v1
AI_REPORT_API_KEY=...
AI_REPORT_MODEL=gpt-4.1-mini
```

## 운영 DB 연결

현재 `B-report.html`의 더미 입력을 없애고 백엔드에서 다음 데이터를 조회해 `AiReportRequest`와 같은 형태의 스냅샷을 만든다.

- 고장 설비·원인·시각: `downtime_event`, `downtime_code`, `equipment`, `alarm`
- 목표 생산량: `production_target`
- 현재 생산량과 불량: 공정별 데이터 및 `inspection_result`
- 설비 상태: `equipment_status_history`, `equipment_signal`
- 재공과 예상 처리량: `product_flow`, `process.cycle_time_sec`
- 현재 도장 경로: `line.current_paint_id`, `paint_route_history`

보고서 생성 시점의 원본 수치와 계산 결과를 JSON으로 함께 저장해야 나중에 같은 보고서를 재현할 수 있다. 기존 `reassignment_report`와 `reassignment_detail`을 확장하거나 아래 필드를 가진 별도 테이블을 권장한다.

```sql
CREATE TABLE ai_report (
  report_id UUID PRIMARY KEY,
  downtime_id BIGINT REFERENCES downtime_event(downtime_id),
  generated_at TIMESTAMP NOT NULL DEFAULT now(),
  generated_by INTEGER REFERENCES users(user_id),
  model VARCHAR(80) NOT NULL,
  prompt_version VARCHAR(30) NOT NULL,
  input_snapshot JSONB NOT NULL,
  calculated_plan JSONB NOT NULL,
  report_content JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'DRAFT'
);
```

## 중요한 설계 원칙

- 부족 수량, 라인 능력, 배정 수량은 Java 서비스에서 계산한다. LLM에 산술과 최종 의사결정을 맡기지 않는다.
- LLM에는 필요한 최소 데이터만 JSON으로 전달하고, DB 전체나 개인정보는 보내지 않는다.
- 프롬프트 버전, 모델, 입력 스냅샷, 응답을 저장한다.
- JSON 응답 스키마를 검증하고 실패 시 재시도 1회 또는 템플릿 보고서로 대체한다.
- 호출 시간 제한, 비용 제한, 사용자별 요청 제한을 둔다.
- 보고서 승인은 별도 상태로 관리하며 승인 전에는 생산계획을 변경하지 않는다.
- 실제 계획 반영 API는 보고서 생성 API와 분리한다.

## 다음 개발 순서

1. `downtimeId` 하나만 받는 생성 API를 추가하고 DB 조회 서비스에서 입력 스냅샷을 조립한다.
2. 납기 데이터가 현재 스키마에 없으므로 주문·납기 테이블 또는 외부 ERP 연동 기준을 확정한다.
3. `ai_report` 저장과 목록·상세 조회 API를 추가한다.
4. 프론트의 더미 폼을 고장 이벤트 선택 화면으로 교체한다.
5. 관리자 승인 후 별도 생산계획 수정 API를 호출하게 한다.
6. 프롬프트 회귀 테스트와 실제 장애 시나리오 평가 세트를 만든다.
