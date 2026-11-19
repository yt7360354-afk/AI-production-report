# AI 생산 리포트

생산 현장의 **일일 생산 마감 보고서**와 **AI 계획수정 보고서**를 화면에서 작성하고 Word(.doc) / PDF로 내려받는 데모입니다.

| 화면 | 주소 |
|---|---|
| 계획수정 보고서 (메인) | http://127.0.0.1:5174/wireframes/%ED%9B%84%EB%B3%B4/B-report.html |
| 일일 생산 리포트 | http://127.0.0.1:5174/wireframes/%ED%9B%84%EB%B3%B4/B-daily.html |

## 실행

필요한 것: Node.js 20 이상, JDK 17 이상

```powershell
.\run-report.ps1
```

백엔드(8080)와 프론트(5174)를 백그라운드로 띄우고 브라우저를 엽니다. 로그는 `logs/` 에 남습니다.

직접 실행할 때:

```powershell
cd backend;  .\gradlew.bat bootRun      # http://localhost:8080
cd frontend; npm install; npm run dev    # http://127.0.0.1:5174  (/api → 8080 프록시)
```

## 구성

```
frontend/
  wireframes/후보/
    B-report.html      계획수정 보고서: AI 생성 API 호출, 값 수정, .doc/PDF
    B-daily.html       일일 생산 리포트: 마감 기록 목록, 보고서 생성, .doc/PDF (데모 데이터)
    b.css              공용 스타일
    b.js, data.js      공용 헤더
  public/templates/
    production-plan-report-template.doc   계획수정 보고서 Word 양식
    daily-report-template.doc             일일 보고서 Word 양식
  vite.config.js       5174 포트, /api → 8080 프록시
backend/               Spring Boot 3.5 (Java 17)
  src/main/java/com/gadong/sfaas/report/
    AiReportController   POST /api/v1/ai-reports/generate
    AiReportService      부족 수량 계산, 라인별 재배정, 보고서 문장 생성(mock 또는 LLM)
    AiReportRequest / AiReportResponse / AiReportProperties / AiReportConfig
docs/
  AI_REPORT_GUIDE.md   설계 원칙과 운영 전환 가이드
  INTEGRATION_GUIDE.md 팀 API 명세서 v3 · DB 스키마 v0.3.9 기준 프론트·백엔드 연동 가이드
  form-source/DAILYREPORT양식.htm   일일 보고서 Word 양식 원본
tools/daily-template/  양식 원본 → 템플릿(.doc) 변환 스크립트
```

## 보고서 생성 방식

- **계획수정 보고서**: 화면이 `POST /api/v1/ai-reports/generate` 로 고장 설비·실적·라인 조건·추가 요청을 보냅니다. 부족 수량과 라인별 배정은 Java 서비스가 계산하고, 보고서 문장은
  - 기본(시연) 모드: API 키 없이 템플릿 문장으로 생성
  - 운영 모드: 아래 환경 변수를 설정하면 OpenAI 호환 LLM으로 생성
- **일일 생산 리포트**: 현재는 프론트의 데모 데이터로 생성합니다(백엔드 호출 없음).
- **Word(.doc) 내려받기**: `public/templates/` 양식에 화면 보고서 값을 채워 A4 한 장으로 만듭니다.

운영 모드 환경 변수 (키는 서버 환경 변수에만 두고 코드·Git에 넣지 않습니다):

```text
AI_REPORT_MOCK=false
AI_REPORT_API_KEY=...
AI_REPORT_BASE_URL=https://api.openai.com/v1
AI_REPORT_MODEL=gpt-4.1-mini
```

## 일일 보고서 양식 수정

1. `docs/form-source/DAILYREPORT양식.htm` 을 Word로 열어 서식·표 크기를 고치고 같은 형식(웹 페이지)으로 저장
2. 템플릿 다시 만들기

```powershell
python tools/daily-template/dr_make_template.py docs/form-source/DAILYREPORT양식.htm frontend/public/templates/daily-report-template.doc template-report.txt
```

양식의 예시 값은 자리표시(`{{DOC_NO}}` 등)로 바뀌고, 반복되는 표 행은 첫 행을 원형으로 사용합니다. 표의 행·열 구성을 바꾸면 스크립트도 함께 수정해야 합니다.
