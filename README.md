# AI Production Report

설비 비가동과 생산실적을 기반으로 생산계획 수정 검토 보고서를 생성하는 데모 프로젝트입니다.

## 구성

- `frontend`: Vite 기반 생산 운영 화면과 AI 보고서 페이지
- `backend`: Spring Boot 기반 AI 보고서 생성 API
- `schema.sql`, `seed.sql`: 데이터베이스 구조와 더미 데이터
- `AI_REPORT_GUIDE.md`: LLM 연동 및 실행 가이드

## 주요 기능

- 현재 생산계획과 설비 조건을 이용한 보고서 생성
- A4 형식 화면 보고서
- 기존 Word 템플릿 기반 DOC 다운로드
- PDF 인쇄 및 다운로드
- Mock 모드와 OpenAI 호환 LLM API 연동 지원

## 실행

자세한 설정과 실행 방법은 `AI_REPORT_GUIDE.md`를 확인하세요.

