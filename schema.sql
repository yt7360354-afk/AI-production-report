-- =====================================================================
-- 라인 가동 현황 모니터링 시스템 · DB 스키마 (PostgreSQL)
-- 1조 가동가동해 · 작성 2026-11-18 · v0.3.9
--
-- 실행 방법:  psql -U postgres -d sfaas -f schema.sql
-- 이 파일이 DB 구조의 "정답지"예요. 테이블을 바꿀 땐 이 파일을 고치고 GitHub에 올려요.
-- 백엔드 JPA 설정은 spring.jpa.hibernate.ddl-auto=validate 로 맞춰주세요.
--
-- ★ 현재 처리 시간 (v0.3.9, seed.sql): 슬리팅 16 · 프레스 17 (1대당, 라인에 4대) · 용접 17 · 도장 4 · 비전 검사 7초
--   라인 박자 16초. 비전 검사기가 병목이라 검사 앞에 재공이 쌓여요. 아래 버전별 기록의 처리 시간은 그때 값이에요.
--
-- v0.3.9 변경 (11/18 백엔드 요청: 설비마다 들어간·나간 시각 → 재공·처리 중·대기·CT·제품 추적)
--   · 🆕 product_flow (공정 이동 기록): 제품이 설비 1대를 거칠 때마다 1줄. 들어갈 때 INSERT(started_at), 나갈 때 UPDATE(ended_at)
--       프레스는 PR1~PR4가 각각 1줄. NG 폐기 제품은 그 설비 줄의 ended_at까지만 (다음 설비 줄 없음). line_id 항상 채움
--   · 역할 나누기: 공정 테이블 = 측정값 + 판정 결과 (처리가 끝나 값이 있을 때만 씀) / product_flow = 이동 시각
--       공정 테이블 구조는 v0.3.8 그대로 (시각 칸 추가 없음)
--   · measured_at = 처리 끝난 시각으로 고정, 덮어쓰지 않음 (프레스는 PR1 끝난 시각). press_data.equipment_id = 마지막으로 끝낸 단
--   · 공정 테이블 INSERT와 product_flow ended_at은 같은 시점·같은 시각 값 (Node-RED가 한 SQL 문장으로 씀)
--   · 기존 DB는 alter_v0.3.9.sql
--
-- v0.3.8 변경 (11/17 백엔드 요청: 제품 하나를 공정 끝까지 추적)
--   · 슬리팅 투입 때 product_id가 생기고(예: A-20261117-0001) 모든 공정 데이터에 같은 product_id가 붙어요
--   · slitting_data, press_data, welding_data, painting_data에 product_id VARCHAR(30) UNIQUE 추가 (제품 1개 = 1줄)
--   · press_data: 제품 1개 = 1줄. PR1 통과 때 INSERT, PR2~PR4는 같은 줄에 UPDATE
--       PR1 = pressure_left, PR2 = pressure_right, PR3 = pressure_diff(🆕 칸), PR4 = press_time
--       equipment_id·measured_at은 마지막으로 지난 프레스로 바뀌어요 (PR4면 프레스 완료)
--       값이 붙을 때마다 Node-RED가 result를 비워서 백엔드가 다시 판정해요 (NG면 그대로 둠)
--   · painting_data: 제품이 도장조에 담길 때의 용액 상태를 product_id와 함께 1줄로
--   · grants.sql: Node-RED에 press_data 고쳐 쓰기(UPDATE) 권한 추가
--
-- v0.3.7 변경 (11/17): 프레스를 1대당 17초로 바로잡음 (v0.3.6의 "4대 합쳐 17초"는 잘못 전달된 값)
--
-- v0.3.6 변경 (11/17 처리 시간 재조정, seed.sql만 바뀜)
--   · [지난 값] 프레스 4대 합쳐 17초(1대당 4.25초) · 도장 4초 · 비전 검사 7초
--
-- v0.3.5 변경 (11/17 아키텍처 확정: Node-RED가 DB에 원시 값 저장 → 백엔드가 조회해서 판정·저장)
--   · equipment_signal 추가: Node-RED가 설비 상태 신호(heartbeat)·고장 신호를 설비마다 1줄로 덮어씀
--     → 백엔드가 last_seen_at으로 DC(10초 이상 끊김), fault로 D를 판정
--   · [지난 값] 처리 시간: 슬리팅 16 · 프레스 17 ×4 · 용접 17 · 도장 2 · 검사 3초
--   · 측정값 result는 Node-RED가 비워서 저장하고 백엔드가 판정해서 채움 (기존 구조 그대로)
--
-- v0.3.4 변경 (11/17 팀 결정)
--   · reassignment_report 승인 칸 복구 (재배정을 할 수도 있어서 칸만 두고 비워 둠)
--   · coil_receipt.product_qty 추가: 코일 1롤 = 제품 20개 → 입고→슬리팅 재공품 계산에 포함
--   · chat_message 테이블 추가 (H-01·H-02, 개발은 후순위)
--   · 상태 판정 규칙: 설비가 생존 신호(heartbeat)를 주기적으로 보냄 (v0.3.5: Node-RED가 equipment_signal에 기록) → DC = 생존 신호 10초 이상 끊김,
--     I = 생존 신호는 오는데 처리할 제품이 없음 (재공 0). 생존 신호는 판정에만 쓰고 DB에 저장하지 않음
--
-- v0.3.3 변경 (11/17 백엔드 피드백 3차)
--   · reassignment_report의 승인 칸(approved, approved_by, approved_at) 삭제 → 계획서 작성까지만
--   · [지난 값] 공용 설비 처리 시간: 도장 2→1초, 검사 2→0.5초
--   · 규칙 주석 정리: DC=가동, I(대기)=설비 정상인데 처리할 제품 없음, COIL은 재공 계산에서 제외
--   · DB에 넣지 않기로 한 것: equipment.dataSource(공정으로 알 수 있음), 채팅 테이블(P3)
--
-- v0.3.2 변경 (11/16 백엔드 피드백 2차)
--   · 설비 표시명을 API 형식으로 (seed.sql): 'A라인 프레스 1호기', '도장 1호기', '비전 검사 1호기'
--   · painting_data.line_id 추가 (공용 도장의 라인별 불량 집계)
--   · downtime_event.stop_group_id 추가 (라인 단위 계획정지 묶음 번호 = API stopId) + stop_group_seq
--   · equipment_status_history.downtime_id 추가 (상태 구간 ↔ 비가동 연결)
--
-- v0.3.1 변경 (11/16 백엔드 피드백): 테이블 이름 3개를 API 명세서에 맞춤
--   inspection → inspection_result, status_log → equipment_status_history, downtime → downtime_event
--
-- v0.3 변경 (11/16 회의 결정)
--   · 설비 ID·공정 코드를 API 명세서 방식으로 (A-PR1, PRESS / WELDING ...)
--   · 비가동 코드를 API 영문 코드로 (UP_BREAKDOWN ...) + 알람 UP_ALARM 분리
--   · 관리값 기준(threshold)을 공정별 → 설비별로
--   · 상태에 DC(통신 끊김) 추가
--   · alarm, paint_route_history 테이블 추가 / 라인별 현재 도장 설비, 검사의 도장 설비 칸 추가
--   · 생산 능력: line.capacity_per_hour 삭제 → process.cycle_time_sec(제품 1개 처리 초)
--   · users에 email, memo, last_login_at 추가
-- =====================================================================

-- 다시 실행해도 되도록 기존 테이블을 지우고 새로 만들어요. (데이터도 같이 지워짐!)
DROP TABLE IF EXISTS inspection, status_log, downtime,   -- v0.3까지의 예전 이름
    product_flow, equipment_signal, chat_message, alarm, paint_route_history,
    reassignment_detail, reassignment_report, downtime_event, equipment_status_history,
    inspection_result, painting_data, welding_data, press_data, slitting_data, coil_receipt,
    production_target, threshold, users, downtime_code, equipment, line, process CASCADE;
DROP SEQUENCE IF EXISTS stop_group_seq;


-- =====================================================================
-- ① 기준정보 (거의 안 바뀌는 데이터, seed.sql로 미리 입력)
-- =====================================================================

-- 공정: 입고 → 슬리팅 → 프레스 → 용접 → 도장 → 검사
CREATE TABLE process (
    process_id      VARCHAR(12)  PRIMARY KEY,       -- 예: 'PRESS', 'WELDING'
    process_name    VARCHAR(20)  NOT NULL,          -- 예: '프레스'
    seq             SMALLINT     NOT NULL UNIQUE,   -- 흐름 순서 (1~6)
    cycle_time_sec  NUMERIC(6,2) NOT NULL DEFAULT 0 -- 제품 1개 처리 시간(초). 시연용으로 짧게 잡은 값
);

-- 라인: A~F (6개)
-- 라인 생산 능력 = 라인 안에서 가장 느린 공정 기준 (프레스·용접 17초 → 시간당 약 211개)
CREATE TABLE line (
    line_id           VARCHAR(5)  PRIMARY KEY,      -- 'A' ~ 'F'
    line_name         VARCHAR(20) NOT NULL,         -- 'A라인'
    default_paint_id  VARCHAR(20),                  -- 기본 도장 설비 (A·B·C → PT1, D·E·F → PT2)
    current_paint_id  VARCHAR(20)                   -- 지금 쓰는 도장 설비 (경로 전환 시 바뀜)
);

-- 설비: 39대 (슬리팅 6 · 프레스 24 · 용접 6 · 도장 2 · 검사 1)
-- ID 규칙(API 명세서): A-SL / A-PR1~4 / A-WD, 공용: PT1, PT2, VI
CREATE TABLE equipment (
    equipment_id    VARCHAR(20) PRIMARY KEY,        -- 코드용 ID. 예: 'A-PR1'
    equipment_name  VARCHAR(30) NOT NULL UNIQUE,    -- 화면 표시명. 예: 'A라인 프레스 1호기'
    process_id      VARCHAR(12) NOT NULL REFERENCES process(process_id),
    line_id         VARCHAR(5)  REFERENCES line(line_id),  -- 공용 설비(도장·검사)는 NULL
    seq_no          SMALLINT    NOT NULL,           -- 같은 라인·공정 안의 번호 (프레스 1~4)
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE
);

-- 라인 → 도장 설비 연결 (equipment가 만들어진 뒤에 걸어야 해서 따로 추가)
ALTER TABLE line
    ADD CONSTRAINT fk_line_default_paint FOREIGN KEY (default_paint_id) REFERENCES equipment(equipment_id),
    ADD CONSTRAINT fk_line_current_paint FOREIGN KEY (current_paint_id) REFERENCES equipment(equipment_id);

-- 비가동 코드: 설비가 멈춘 "이유" 목록 (API 명세서 영문 코드, RFP 기준 + 알람 분리)
CREATE TABLE downtime_code (
    code         VARCHAR(20) PRIMARY KEY,           -- 'PL_SHIFT', 'UP_BREAKDOWN' ...
    code_name    VARCHAR(30) NOT NULL,              -- '장비고장'
    is_planned   BOOLEAN     NOT NULL,              -- TRUE = 계획정지(손실 아님), FALSE = 비계획정지(손실)
    description  VARCHAR(100)
);

-- 사용자 (로그인 계정). 역할 종류는 추후 결정
CREATE TABLE users (
    user_id        SERIAL       PRIMARY KEY,
    login_id       VARCHAR(30)  NOT NULL UNIQUE,
    password_hash  VARCHAR(100) NOT NULL,           -- 비밀번호 원문 저장 금지! Spring Security BCrypt 결과를 저장
    user_name      VARCHAR(20)  NOT NULL,           -- 조치 담당자 이름은 여기서 가져와요
    role           VARCHAR(20)  NOT NULL DEFAULT 'MANAGER',
    email          VARCHAR(100),
    memo           VARCHAR(200),
    last_login_at  TIMESTAMP,
    created_at     TIMESTAMP    NOT NULL DEFAULT now()
);

-- 관리값 기준 (SCR-009): 설비마다 관리 항목의 상·하한
-- 처음에는 공정 기준값을 같은 종류 설비 전체에 복사해 두고, 필요한 설비만 수정해요
CREATE TABLE threshold (
    threshold_id  SERIAL      PRIMARY KEY,
    equipment_id  VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    item_name     VARCHAR(30) NOT NULL,             -- 수집 테이블의 컬럼명과 같게. 예: 'pressure_left'. 예: 'pressure_diff'(압력 차, PR3)
    item_label    VARCHAR(30) NOT NULL,             -- 화면 표시명. 예: '좌 압력'
    unit          VARCHAR(10),
    lower_limit   NUMERIC(12,3),
    upper_limit   NUMERIC(12,3),
    updated_at    TIMESTAMP   NOT NULL DEFAULT now(),
    updated_by    INTEGER     REFERENCES users(user_id),
    UNIQUE (equipment_id, item_name)
);


-- =====================================================================
-- ② 계획
-- =====================================================================

-- 생산 목표 (SCR-008): 날짜별 · 라인별 목표 수량
CREATE TABLE production_target (
    target_date  DATE       NOT NULL,
    line_id      VARCHAR(5) NOT NULL REFERENCES line(line_id),
    target_qty   INTEGER    NOT NULL CHECK (target_qty >= 0),
    created_by   INTEGER    REFERENCES users(user_id),
    created_at   TIMESTAMP  NOT NULL DEFAULT now(),
    PRIMARY KEY (target_date, line_id)              -- 같은 날 같은 라인 목표는 1개만
);


-- =====================================================================
-- ③ 수집 데이터 (사이클마다 쌓임)
--    공정마다 측정 항목이 달라서 테이블을 나눴어요.
--    측정값 한 줄 = 제품 1개. 평균 내지 않고 전부 저장해요.
--    result가 NG면 그 제품은 바로 폐기되고 다음 공정으로 가지 않아요 (재검 없음).
--    result는 백엔드가 threshold와 비교해서 채워요.
-- =====================================================================

-- 코일 입고 (설비 없음, 가상 데이터)
CREATE TABLE coil_receipt (
    receipt_id   BIGSERIAL   PRIMARY KEY,
    material_id  VARCHAR(30) NOT NULL,              -- 원자재 제품ID (한 줄 = 코일 1롤)
    received_at  TIMESTAMP   NOT NULL,              -- 입고시각
    product_qty  INTEGER     NOT NULL DEFAULT 20 CHECK (product_qty > 0)  -- 이 코일 1롤로 만들 수 있는 제품 수 (11/17: 1롤 = 20개)
);
-- 입고→슬리팅 재공품 = 입고된 코일의 product_qty 합 − 슬리팅 처리 수 (공장 전체 기준. 코일은 라인 구분 없음)

-- 슬리팅 (실습 모터·인버터 PLC) ※ PLC 확정 후 컬럼 수정 예정
CREATE TABLE slitting_data (
    id            BIGSERIAL   PRIMARY KEY,
    product_id    VARCHAR(30) UNIQUE,               -- 제품 ID (슬리팅 투입 때 생김, 예: A-20261117-0001)
    equipment_id  VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    measured_at   TIMESTAMP   NOT NULL,             -- 생산시각
    torque        NUMERIC(10,3),
    current       NUMERIC(10,3),
    voltage       NUMERIC(10,3),
    result        VARCHAR(2)  CHECK (result IN ('OK', 'NG'))   -- 공정 판정: OK 양품 / NG 불량(폐기)
);

-- 프레스 (KAMP 7번 프레스기)
-- 제품 1개 = 1줄: PR1 통과 때 생기고(INSERT) PR2~PR4가 같은 줄에 값을 채워요(UPDATE). 아직 안 지난 프레스 값은 NULL
CREATE TABLE press_data (
    id              BIGSERIAL   PRIMARY KEY,
    product_id      VARCHAR(30) UNIQUE,             -- 제품 ID (제품 1개 = 1줄)
    equipment_id    VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),   -- 마지막으로 끝낸 단 (PR4면 프레스 완료)
    measured_at     TIMESTAMP   NOT NULL,           -- PR1 끝난 시각 (v0.3.9: 고정, 덮어쓰지 않음. 단별 시각은 product_flow)
    pressure_left   NUMERIC(10,3),                  -- 좌 압력 (PR1)
    pressure_right  NUMERIC(10,3),                  -- 우 압력 (PR2)
    pressure_diff   NUMERIC(10,3),                  -- 압력 차 좌−우 (PR3)
    press_time      NUMERIC(10,3),                  -- 가압 시간 (PR4, 단위 0.01초)
    pressure_total  NUMERIC(10,3),                  -- 압력 합계 (지금은 채우지 않음)
    result          VARCHAR(2)  CHECK (result IN ('OK', 'NG'))   -- 공정 판정: OK 양품 / NG 불량(폐기)
);

-- 용접 (KAMP 5번 스폿용접기)
CREATE TABLE welding_data (
    id            BIGSERIAL   PRIMARY KEY,
    product_id    VARCHAR(30) UNIQUE,               -- 제품 ID
    equipment_id  VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    measured_at   TIMESTAMP   NOT NULL,
    press_force   NUMERIC(10,3),                    -- 가압력
    current       NUMERIC(10,3),                    -- 전류
    voltage       NUMERIC(10,3),                    -- 전압
    weld_time     NUMERIC(10,3),                    -- 통전시간
    result        VARCHAR(2)  CHECK (result IN ('OK', 'NG'))   -- 공정 판정: OK 양품 / NG 불량(폐기)
);

-- 도장 (KAMP 표면처리·도금욕 대체)
-- 제품 단위: 제품이 도장조에 담길 때 그 순간의 용액 상태(pH·온도·전류·전압)를 1줄로. 기준 이탈이면 그 제품이 NG
CREATE TABLE painting_data (
    id            BIGSERIAL   PRIMARY KEY,
    product_id    VARCHAR(30) UNIQUE,               -- 제품 ID
    equipment_id  VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    measured_at   TIMESTAMP   NOT NULL,             -- 도장 끝난 시각 (들어간 시각은 product_flow)
    line_id       VARCHAR(5)  REFERENCES line(line_id),  -- 이 제품이 온 라인 (도장은 공용이라 꼭 채워주세요)
    ph            NUMERIC(6,3),
    temperature   NUMERIC(8,3),
    current       NUMERIC(10,3),
    voltage       NUMERIC(10,3),
    result        VARCHAR(2)  CHECK (result IN ('OK', 'NG'))   -- 공정 판정: OK 양품 / NG 불량(폐기)
);

-- 출고 검사 (비전 검사기 1대, 6개 라인 공용). 비전 판정만 해요 (재검 없음)
-- line_id: 이 제품이 어느 라인에서 왔는지. 라인별 생산량은 이 칸으로 셉니다.
CREATE TABLE inspection_result (
    inspection_id      BIGSERIAL   PRIMARY KEY,
    equipment_id       VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    product_id         VARCHAR(30) NOT NULL UNIQUE,  -- 완제품ID
    line_id            VARCHAR(5)  NOT NULL REFERENCES line(line_id),
    paint_equipment_id VARCHAR(20) REFERENCES equipment(equipment_id),  -- 거쳐 온 도장 설비 (PT1/PT2)
    result             VARCHAR(2)  NOT NULL CHECK (result IN ('OK', 'NG')),  -- OK 양품 / NG 비전 불량
    inspected_at       TIMESTAMP   NOT NULL,         -- 생산(검사)시각
    shipped_at         TIMESTAMP                     -- 출고시각 (불량이면 NULL)
);

-- 조회가 잦은 "설비 + 시간" 조합에 인덱스 (책의 색인처럼 찾기를 빠르게)
CREATE INDEX idx_slitting_eq_time ON slitting_data (equipment_id, measured_at);
CREATE INDEX idx_press_eq_time    ON press_data    (equipment_id, measured_at);
CREATE INDEX idx_welding_eq_time  ON welding_data  (equipment_id, measured_at);
CREATE INDEX idx_painting_eq_time ON painting_data (equipment_id, measured_at);
CREATE INDEX idx_painting_line_time ON painting_data (line_id, measured_at);
CREATE INDEX idx_inspection_result_line_time ON inspection_result (line_id, inspected_at);
CREATE INDEX idx_coil_time        ON coil_receipt  (received_at);

-- 🆕 v0.3.9 공정 이동 기록: 제품이 설비 1대를 거칠 때마다 1줄 (프레스는 PR1~PR4 각각 1줄)
-- 들어갈 때 INSERT(started_at), 나갈 때 같은 줄 UPDATE(ended_at). 나갈 때는 공정 테이블 INSERT와 같은 시각 값
-- 처리 중 = started_at 있음 + ended_at 없음 / 설비 사이 재공 = 앞 설비 ended_at 있음 + 다음 설비 줄 없음
-- NG로 폐기된 제품은 그 설비 줄의 ended_at까지만 써요 (다음 설비 줄 없음). 코일 입고는 넣지 않아요
CREATE TABLE product_flow (
    flow_id       BIGSERIAL   PRIMARY KEY,
    product_id    VARCHAR(30) NOT NULL,             -- 제품 ID (A-20261118-0001)
    equipment_id  VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    line_id       VARCHAR(5)  NOT NULL REFERENCES line(line_id),   -- 제품이 온 라인 = 제품 ID 앞자리 (도장·검사도 항상 채움)
    started_at    TIMESTAMP,                        -- 설비에 들어간 시각
    ended_at      TIMESTAMP,                        -- 설비에서 나간 시각 (NULL = 처리 중)
    UNIQUE (product_id, equipment_id),              -- 한 제품은 한 설비를 한 번만 거쳐요
    CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX idx_flow_open    ON product_flow (equipment_id) WHERE ended_at IS NULL;   -- 처리 중 조회용
CREATE INDEX idx_flow_started ON product_flow (equipment_id, started_at);              -- CT·시간대 조회용
CREATE INDEX idx_flow_line    ON product_flow (line_id, equipment_id);                 -- 라인별 재공용


-- =====================================================================
-- ④ 이벤트 · 이력 (Spring Boot가 판정해서 기록)
-- =====================================================================

-- 상태 이력: 설비 상태가 바뀔 때마다 한 줄. 끝나지 않은 구간은 ended_at = NULL
-- R 가동 · S 정지(계획) · I 대기 · D 고장/알람 · DC 통신 끊김
-- ※ DC는 설비가 돌고 있을 수 있어서 가동률 계산에서는 "가동(R)"으로 봐요 (11/16 결정)
-- ※ I(대기) = 설비는 정상(생존 신호 수신 중)인데 처리할 제품이 없음 (재공 0). 슬리팅은 코일 재공(입고 product_qty 합 − 슬리팅 수)이 0일 때
-- ※ DC = 생존 신호(heartbeat)가 10초 이상 끊김. I가 오래 이어져도 DC가 되지 않아요
-- ※ 계획정지(S) 시간 안에서 난 고장은 손실로 세지 않아요 (11/16 결정)
CREATE TABLE equipment_status_history (
    log_id        BIGSERIAL   PRIMARY KEY,
    equipment_id  VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    status        VARCHAR(2)  NOT NULL CHECK (status IN ('R', 'S', 'I', 'D', 'DC')),
    started_at    TIMESTAMP   NOT NULL,
    ended_at      TIMESTAMP,
    downtime_id   BIGINT,                           -- S·I·D 구간이면 해당 비가동 번호 (R·DC는 NULL). FK는 아래에서 연결
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX idx_status_history_eq_time ON equipment_status_history (equipment_id, started_at);

-- 비가동 이력 (SCR-002, 003, 006): 멈춘 구간 + 사유 코드 + 조치
-- 저장은 전부 하고, 비가동 "건수"는 조회할 때 1분 이상만 셉니다 (11/16 결정)
-- 계획정지는 일정표 없이 관리자가 원하는 시점에 시작·종료 (status 'S' + PL_ 코드)
-- 라인 단위로 멈추면 그 라인 설비 6대에 한 줄씩 + 같은 stop_group_id (공용 설비 도장·검사는 제외)
CREATE TABLE downtime_event (
    downtime_id     BIGSERIAL   PRIMARY KEY,
    equipment_id    VARCHAR(20) NOT NULL REFERENCES equipment(equipment_id),
    status          CHAR(1)     NOT NULL CHECK (status IN ('S', 'I', 'D')),
    code            VARCHAR(20) NOT NULL REFERENCES downtime_code(code),
    detail          VARCHAR(200),                   -- 예: '압력 상한 초과'
    started_at      TIMESTAMP   NOT NULL,
    ended_at        TIMESTAMP,                      -- NULL = 진행중
    action_memo     VARCHAR(500),                   -- 조치 메모
    action_user_id  INTEGER     REFERENCES users(user_id),  -- 조치한 담당자 (계획정지는 시작한 관리자)
    action_at       TIMESTAMP,
    stop_group_id   BIGINT,                         -- 라인 단위 계획정지 묶음 번호 (API stopId). 같은 정지면 같은 번호
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX idx_downtime_event_eq_time ON downtime_event (equipment_id, started_at);
CREATE INDEX idx_downtime_event_code    ON downtime_event (code);
CREATE INDEX idx_downtime_event_group   ON downtime_event (stop_group_id);

-- 라인 단위 계획정지 번호 발급용: 라인 정지 1번 = nextval 1번 → 그 라인 설비 6대(슬리팅·프레스 4·용접) 행에 같은 번호
CREATE SEQUENCE stop_group_seq;

-- 상태 이력 → 비가동 연결 (downtime_event가 만들어진 뒤에 걸어야 해서 여기서 추가)
ALTER TABLE equipment_status_history
    ADD CONSTRAINT fk_status_history_downtime FOREIGN KEY (downtime_id) REFERENCES downtime_event(downtime_id);

-- 알람 (M-04~06, W-02): 관리값 상·하한 이탈 → 발생(RAISED), 범위 복귀 → 해제(CLEARED)
CREATE TABLE alarm (
    alarm_id        BIGSERIAL    PRIMARY KEY,
    equipment_id    VARCHAR(20)  NOT NULL REFERENCES equipment(equipment_id),
    item_name       VARCHAR(30),                    -- 벗어난 항목. 예: 'pressure_total' (고장 신호면 NULL)
    measured_value  NUMERIC(12,3),                  -- 그때 측정값
    lower_limit     NUMERIC(12,3),                  -- 그때 기준 (나중에 기준이 바뀌어도 기록 유지)
    upper_limit     NUMERIC(12,3),
    level           VARCHAR(10)  NOT NULL DEFAULT 'CRITICAL' CHECK (level IN ('WARNING', 'CRITICAL')),
    message         VARCHAR(200) NOT NULL,          -- 예: '압력 합계 상한 초과'
    raised_at       TIMESTAMP    NOT NULL,          -- 발생 시각
    cleared_at      TIMESTAMP,                      -- 해제 시각 (NULL = 진행중)
    acked_by        INTEGER      REFERENCES users(user_id),  -- 확인한 사람
    acked_at        TIMESTAMP,
    raw_values      JSONB,                          -- 알람 순간의 원시 값 묶음 (원인 분석용)
    CHECK (cleared_at IS NULL OR cleared_at >= raised_at)
);
CREATE INDEX idx_alarm_eq_time ON alarm (equipment_id, raised_at);
CREATE INDEX idx_alarm_active  ON alarm (raised_at) WHERE cleared_at IS NULL;  -- 활성 알람 조회용

-- 설비 신호 (v0.3.5): 설비마다 1줄. Node-RED가 상태 신호(1초마다)·고장 신호를 받을 때마다 덮어써요 (UPSERT)
-- 백엔드 판정: now() - last_seen_at > 10초 → DC, fault = 1 → D. 이력은 남기지 않음 (상태 변화는 equipment_status_history에)
CREATE TABLE equipment_signal (
    equipment_id  VARCHAR(20) PRIMARY KEY REFERENCES equipment(equipment_id),
    last_seen_at  TIMESTAMP   NOT NULL,             -- 마지막 상태 신호 받은 시각
    fault         SMALLINT    NOT NULL DEFAULT 0 CHECK (fault IN (0, 1)),  -- 고장 신호 0 정상 / 1 고장
    updated_at    TIMESTAMP   NOT NULL DEFAULT now()
);

-- 도장 경로 전환 이력 (M-09): 라인이 쓰는 도장 설비를 바꾼 기록
CREATE TABLE paint_route_history (
    history_id     BIGSERIAL    PRIMARY KEY,
    line_id        VARCHAR(5)   NOT NULL REFERENCES line(line_id),
    from_paint_id  VARCHAR(20)  REFERENCES equipment(equipment_id),
    to_paint_id    VARCHAR(20)  NOT NULL REFERENCES equipment(equipment_id),
    reason         VARCHAR(200),
    changed_by     INTEGER      REFERENCES users(user_id),
    changed_at     TIMESTAMP    NOT NULL DEFAULT now()
);
CREATE INDEX idx_paint_route_line_time ON paint_route_history (line_id, changed_at);

-- 재배정 계획서 (SCR-007): 정지 30분 이상 → 손실 수량 → 여유 라인 추천
-- ※ 지금은 계획서 작성까지만. 재배정을 할 수도 있어서 승인 칸은 두고 비워 둠 (v0.3.4)
CREATE TABLE reassignment_report (
    report_id     BIGSERIAL   PRIMARY KEY,
    downtime_id   BIGINT      NOT NULL REFERENCES downtime_event(downtime_id),
    loss_qty      INTEGER     NOT NULL,             -- 손실 수량 = 정지 시간 × 라인 시간당 생산 능력
    created_at    TIMESTAMP   NOT NULL DEFAULT now(),
    approved      BOOLEAN     NOT NULL DEFAULT FALSE,   -- 관리자 승인 여부 (지금은 안 씀)
    approved_by   INTEGER     REFERENCES users(user_id),
    approved_at   TIMESTAMP
);

-- 계획서의 재배정 표: 어느 라인에 몇 개를 더 맡길지 (라인마다 한 줄)
CREATE TABLE reassignment_detail (
    report_id       BIGINT     NOT NULL REFERENCES reassignment_report(report_id) ON DELETE CASCADE,
    line_id         VARCHAR(5) NOT NULL REFERENCES line(line_id),
    spare_capacity  INTEGER    NOT NULL,            -- 여유 능력 = 최대 − 현재 계획
    added_qty       INTEGER    NOT NULL,            -- 추가 배정 수량
    PRIMARY KEY (report_id, line_id)
);


-- =====================================================================
-- ⑤ 기타
-- =====================================================================

-- 채팅 (H-01 목록, H-02 전송): 공장 전체 채팅방 1개. 개발은 P2
CREATE TABLE chat_message (
    message_id  BIGSERIAL     PRIMARY KEY,
    sender_id   INTEGER       NOT NULL REFERENCES users(user_id),  -- 보낸 사람 (화면에는 users.user_name)
    content     VARCHAR(1000) NOT NULL,                            -- 메시지 내용
    sent_at     TIMESTAMP     NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_sent ON chat_message (sent_at);
