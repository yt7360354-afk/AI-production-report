-- =====================================================================
-- 기준정보 초기 데이터 (schema.sql 실행 후에 실행) · v0.3.9 · 2026-11-18 (v0.3.8에서 내용 변경 없음, 박자 주석만 16초로)
-- 실행 방법:  psql -U postgres -d sfaas -f seed.sql
-- =====================================================================

-- 공정 6개 (코드는 API 명세서 방식)
-- cycle_time_sec: 제품 1개 처리 시간(초). 시연용으로 정한 값 (11/17)
--   라인 박자 16초(라인마다 16초에 1개 투입) → 6개 라인 합계 1분에 22.5개 투입
--   슬리팅 16초, 프레스 1대당 17초 (라인에 4대 → 프레스 구간 통과 68초), 용접 17초
--   도장 4초(3개 라인 공용), 비전 검사 7초(6개 라인 공용 → 1분에 약 8.6개)
--   → 검사기가 병목이라 검사 앞에 재공이 쌓여요 (시연에서 병목·재공을 보여주려는 설정, 11/17)
INSERT INTO process (process_id, process_name, seq, cycle_time_sec) VALUES
    ('COIL',       '코일입고', 1, 0),
    ('SLITTING',   '슬리팅',   2, 16),
    ('PRESS',      '프레스',   3, 17),
    ('WELDING',    '용접',     4, 17),
    ('PAINTING',   '도장',     5, 4),
    ('INSPECTION', '검사',     6, 7);

-- 공용 설비 먼저 (도장 2대, 검사 1대) → 라인이 도장 설비를 가리켜야 해서 순서가 중요해요
INSERT INTO equipment (equipment_id, equipment_name, process_id, line_id, seq_no) VALUES
    ('PT1', '도장 1호기', 'PAINTING',   NULL, 1),   -- A·B·C 라인 기본
    ('PT2', '도장 2호기', 'PAINTING',   NULL, 2),   -- D·E·F 라인 기본
    ('VI',  '비전 검사 1호기', 'INSPECTION', NULL, 1);   -- 6개 라인 공용

-- 라인 6개 (처음에는 기본 도장 설비 = 현재 도장 설비)
INSERT INTO line (line_id, line_name, default_paint_id, current_paint_id) VALUES
    ('A', 'A라인', 'PT1', 'PT1'),
    ('B', 'B라인', 'PT1', 'PT1'),
    ('C', 'C라인', 'PT1', 'PT1'),
    ('D', 'D라인', 'PT2', 'PT2'),
    ('E', 'E라인', 'PT2', 'PT2'),
    ('F', 'F라인', 'PT2', 'PT2');

-- 라인별 설비 36대: 라인마다 슬리팅 1 · 프레스 4 · 용접 1
-- ID 규칙: A-SL / A-PR1~4 / A-WD (B~F 동일)
-- 화면 표시명(API 형식): A라인 슬리팅 1호기 / A라인 프레스 1~4호기 / A라인 용접 1호기
INSERT INTO equipment (equipment_id, equipment_name, process_id, line_id, seq_no)
SELECT l.line_id || '-SL', l.line_id || '라인 슬리팅 1호기', 'SLITTING', l.line_id, 1
FROM line l
UNION ALL
SELECT l.line_id || '-PR' || n, l.line_id || '라인 프레스 ' || n || '호기', 'PRESS', l.line_id, n
FROM line l CROSS JOIN generate_series(1, 4) AS n
UNION ALL
SELECT l.line_id || '-WD', l.line_id || '라인 용접 1호기', 'WELDING', l.line_id, 1
FROM line l;

-- 비가동 코드 11개 (API 명세서 영문 코드, RFP 3번 분류 + 알람 분리)
INSERT INTO downtime_code (code, code_name, is_planned, description) VALUES
    ('PL_SHIFT',     '교대·점심',         TRUE,  '점심시간 정지'),
    ('PL_PM',        '예방보전',          TRUE,  '정기 점검'),
    ('PL_CHANGE',    '모델교체',          TRUE,  '금형 교체'),
    ('PL_SETUP',     '셋업',              TRUE,  '슬리팅 코일·나이프 교체'),
    ('UP_BREAKDOWN', '장비고장',          FALSE, '설비 고장 신호'),
    ('UP_ALARM',     '알람(관리값 이탈)', FALSE, '관리값 상·하한 초과 (SCR-009 기준)'),
    ('UP_SHORTAGE',  '재공부족',          FALSE, '앞 공정 정지로 재료 없음'),
    ('UP_DELAY',     '작업지연',          FALSE, '작업자 투입 지연'),
    ('UP_LABOR',     '노사협의',          FALSE, '노사협의로 인한 정지'),
    ('UP_SAFETY',    '안전문제',          FALSE, '비상정지 버튼'),
    ('UP_ETC',       '기타',              FALSE, '위에 해당하지 않음');

-- 관리값 기준: 설비마다 미리 설정 (11/16 결정)
-- 정하는 방법: KAMP 원본 데이터에서 값의 99.8%가 들어오는 범위 (하위 0.1% ~ 상위 0.1%)
-- 같은 종류 설비에는 처음에 같은 값을 복사해 두고, SCR-009 화면에서 설비별로 수정해요
-- 프레스 24대×1 + 용접 6대×4 + 도장 2대×4 = 56줄 / 슬리팅: 실제 인버터 값 확인 후 추가
-- 프레스 (v0.3.8): press_data는 제품 1개 = 1줄. 프레스 4대가 한 항목씩 값을 채우고, 값이 붙을 때마다 판정
--   PR1 = pressure_left, PR2 = pressure_right, PR3 = pressure_diff, PR4 = press_time. 벗어나면 그 프레스에서 NG·알람
--   pressure_total은 판정 안 함
INSERT INTO threshold (equipment_id, item_name, item_label, unit, lower_limit, upper_limit)
SELECT e.equipment_id, d.item_name, d.item_label, d.unit, d.lower_limit, d.upper_limit
FROM equipment e
JOIN (VALUES
    -- 프레스 (KAMP 7번, 64,359행)
    ('PR1', 'pressure_left',  '좌 압력',        'bar',   270,    285.3),
    ('PR2', 'pressure_right', '우 압력',        'bar',   267,    276.3),
    ('PR3', 'pressure_diff',  '압력 차(좌-우)', 'bar',   -1.8,   12.5),
    ('PR4', 'press_time',     '가압 시간',      '0.01s', 540,    570.6)
) AS d(press_no, item_name, item_label, unit, lower_limit, upper_limit)
  ON e.process_id = 'PRESS' AND e.equipment_id LIKE '%-' || d.press_no;

INSERT INTO threshold (equipment_id, item_name, item_label, unit, lower_limit, upper_limit)
SELECT e.equipment_id, d.item_name, d.item_label, d.unit, d.lower_limit, d.upper_limit
FROM equipment e
JOIN (VALUES
    -- 용접 (KAMP 5번, 11,939행) ※ 가압력은 약 8%가 5~10으로 따로 몰려 있음
    ('WELDING',  'press_force',    '가압력',    'bar',   2.16,   9.27),
    ('WELDING',  'current',        '전류',      'kA',    14.52,  15.07),
    ('WELDING',  'voltage',        '전압',      'V',     2.467,  2.847),
    ('WELDING',  'weld_time',      '통전시간',  'ms',    70,     73),
    -- 도장 (KAMP 도금욕, 50,094행)
    ('PAINTING', 'ph',             'pH',        NULL,    1.51,   5.18),
    ('PAINTING', 'temperature',    '온도',      '℃',     18.54,  27.99),
    ('PAINTING', 'current',        '전류',      'A',     1.63,   4.49),
    ('PAINTING', 'voltage',        '전압',      'V',     1.39,   4.99)
) AS d(process_id, item_name, item_label, unit, lower_limit, upper_limit)
  ON e.process_id = d.process_id;

-- 사용자: 계정은 백엔드가 회원 생성 API(또는 BCrypt 해시)로 넣어요.
-- 비밀번호 원문을 SQL에 쓰면 안 되기 때문에 여기서는 넣지 않아요.
