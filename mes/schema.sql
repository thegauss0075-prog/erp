-- ════════════════════════════════════════════════════════════
--  THE GAUSS VINA · MES 데이터베이스 (Supabase / PostgreSQL)
--  Supabase 화면 → SQL Editor → 이 파일 전체를 붙여 넣고 Run
--  여러 번 실행해도 안전합니다 (이미 있으면 건너뜀)
-- ════════════════════════════════════════════════════════════

-- ── 사용자 권한: Supabase 로그인 이메일 ↔ 역할
--    floor  = 현장 태블릿 (실적·설비 입력)
--    admin  = 관리자 (기준정보 수정·실적 수정/삭제)
--    viewer = 조회만 (공장 TV, 한국 본사)
create table if not exists app_users (
  email text primary key,
  role  text not null check (role in ('floor','admin','viewer')),
  name  text,
  created_at timestamptz default now()
);

-- ── 기준정보
create table if not exists processes (          -- 공정
  code text primary key,
  name text not null,
  name_vi text,
  seq int default 0,
  is_final boolean default false,               -- 마지막 공정(완성 수량으로 셈)
  active boolean default true
);
create table if not exists machines (           -- 설비
  code text primary key,
  name text not null,
  process_code text references processes(code),
  active boolean default true
);
create table if not exists workers (            -- 작업자
  code text primary key,
  name text not null,
  team text,
  active boolean default true
);
create table if not exists stop_reasons (       -- 비가동 사유
  code text primary key,
  name text not null,
  name_vi text,
  planned boolean default false,                -- 계획 정지(휴식·청소)는 가동률에서 뺀다
  seq int default 0
);

-- ── ERP 작업지시 사본 (MES 화면이 ERP에서 받아와 저장)
create table if not exists work_orders (
  wo_id text primary key,                       -- ERP 작업지시 id
  order_no text,
  code text, name text, cat text, unit text,
  plan_qty numeric default 0,
  lot text,
  status text,
  due_date date,
  synced_at timestamptz default now()
);

-- ── 공정 실적
create table if not exists prod_records (
  id bigint generated always as identity primary key,
  wo_id text references work_orders(wo_id),
  order_no text,
  item_code text, item_name text,
  process_code text references processes(code),
  machine_code text references machines(code),
  worker_code text references workers(code),
  start_at timestamptz,
  end_at timestamptz,
  good_qty numeric default 0,
  ng_qty numeric default 0,
  ng_reason text,
  lot_out text,                                 -- 이 공정에서 나온 LOT (보통 작업지시 LOT)
  lots_in jsonb default '[]'::jsonb,            -- 투입 자재 LOT [{code, lot, qty}]
  note text,
  status text default 'done' check (status in ('running','done','void')),
  device text,
  created_by text default auth.email(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  erp_sent_at timestamptz                       -- ERP 실적으로 보낸 시각
);
create index if not exists prod_records_wo on prod_records(wo_id);
create index if not exists prod_records_day on prod_records(created_at);
create index if not exists prod_records_lot on prod_records(lot_out);

-- ── 설비 가동/비가동 이벤트 (상태가 바뀔 때마다 한 줄, 끝나면 ended_at)
create table if not exists machine_events (
  id bigint generated always as identity primary key,
  machine_code text references machines(code),
  state text not null check (state in ('run','stop','setup','idle')),
  reason_code text references stop_reasons(code),
  wo_id text,
  note text,
  started_at timestamptz default now(),
  ended_at timestamptz,
  created_by text default auth.email()
);
create index if not exists machine_events_m on machine_events(machine_code, started_at desc);

-- ── 기본 공정·사유 (필요하면 관리 화면에서 바꾸세요)
insert into processes(code,name,name_vi,seq,is_final) values
  ('WIND','권선','Quấn dây',10,false),('ASSY','조립','Lắp ráp',20,false),('SOLD','납땜','Hàn',30,false),
  ('IMPR','함침','Tẩm sấy',40,false),('TEST','특성검사','Kiểm tra đặc tính',50,false),('VISU','외관검사','Kiểm tra ngoại quan',60,false),('PACK','포장','Đóng gói',70,true)
on conflict (code) do nothing;
insert into stop_reasons(code,name,name_vi,planned,seq) values
  ('MAT','자재 대기','Chờ NVL',false,10),('BRK','설비 고장','Hỏng máy',false,20),('SET','셋업·교체','Thay đổi/Cài đặt',false,30),
  ('QUA','품질 문제','Lỗi chất lượng',false,40),('NOP','작업자 없음','Thiếu người',false,50),
  ('RST','휴식·식사','Nghỉ / Ăn',true,60),('CLN','청소·점검','Vệ sinh / Kiểm tra',true,70),('ETC','기타','Khác',false,90)
on conflict (code) do nothing;

-- ── 권한 (Row Level Security): 로그인한 사람만, 역할에 따라
create or replace function my_role() returns text language sql stable security definer set search_path = public as $$
  select role from app_users where lower(email) = lower(auth.email())
$$;

do $$ declare t text; begin
  foreach t in array array['processes','machines','workers','stop_reasons','work_orders','prod_records','machine_events','app_users'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "read" on %I', t);
    execute format('create policy "read" on %I for select to authenticated using (my_role() is not null)', t);
  end loop;
end $$;

-- 현장(floor)·관리자: 실적·설비 이벤트 입력/수정, 작업지시 사본 갱신
drop policy if exists "write" on prod_records;
create policy "write" on prod_records for insert to authenticated with check (my_role() in ('floor','admin'));
drop policy if exists "update" on prod_records;
create policy "update" on prod_records for update to authenticated using (my_role() = 'admin' or (my_role() = 'floor' and created_by = auth.email() and created_at > now() - interval '1 day'));
drop policy if exists "delete" on prod_records;
create policy "delete" on prod_records for delete to authenticated using (my_role() = 'admin');

drop policy if exists "write" on machine_events;
create policy "write" on machine_events for insert to authenticated with check (my_role() in ('floor','admin'));
drop policy if exists "update" on machine_events;
create policy "update" on machine_events for update to authenticated using (my_role() in ('floor','admin'));

drop policy if exists "write" on work_orders;
create policy "write" on work_orders for insert to authenticated with check (my_role() in ('floor','admin'));
drop policy if exists "update" on work_orders;
create policy "update" on work_orders for update to authenticated using (my_role() in ('floor','admin'));

-- 기준정보: 관리자만
do $$ declare t text; begin
  foreach t in array array['processes','machines','workers','stop_reasons'] loop
    execute format('drop policy if exists "admin" on %I', t);
    execute format('create policy "admin" on %I for all to authenticated using (my_role() = ''admin'') with check (my_role() = ''admin'')', t);
  end loop;
end $$;

-- ── 실시간 전송 켜기 (현장 TV가 바로 바뀌게)
do $$ begin
  begin alter publication supabase_realtime add table prod_records; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table machine_events; exception when duplicate_object then null; end;
end $$;

-- ════════════════════════════════════════════════════════════
--  마지막으로: 로그인 계정을 역할에 연결하세요 (이메일은 실제로 만든 계정으로)
--  Authentication → Users → Add user 로 계정을 먼저 만든 뒤 아래를 고쳐서 실행
-- ════════════════════════════════════════════════════════════
-- insert into app_users(email, role, name) values
--   ('admin@thegauss.vn', 'admin',  '법인장'),
--   ('floor1@thegauss.vn','floor',  '현장 태블릿 1'),
--   ('tv@thegauss.vn',    'viewer', '공장 TV')
-- on conflict (email) do update set role = excluded.role, name = excluded.name;

-- ── [보안 보강] 로그인 안 한 사람은 권한 확인 함수를 직접 부를 수 없게
revoke execute on function public.my_role() from anon, public;
grant execute on function public.my_role() to authenticated;

-- ── [2026-11-06] 품목별 공정 순서(라우팅) + 기본 공정 표시
create table if not exists routings (
  item_code text not null, cat text not null default 'TP',
  process_code text not null references processes(code), seq int not null,
  is_final boolean default false, note text,
  primary key (item_code, cat, process_code));
alter table routings enable row level security;
alter table processes add column if not exists in_default boolean default true;
-- (200kW PCDU 공정 순서는 Supabase에 직접 넣어 두었음: BTP 50~120, TP 130~190)
-- ── [2026-11-06] 공정별 자재 LOT 필수
alter table routings add column if not exists lot_required boolean default false;
-- ── [2026-11-06] 공정별 입력 단위 (예: WIRE 재단 2가닥 = 단품 1개)
alter table routings add column if not exists unit_name text, add column if not exists unit_per numeric default 1;
-- ── [2026-11-06] 계측기 교정 대장 · 설비 일상점검 (Supabase에 적용해 둠: gauges, gauge_cals, check_items, machine_checks + RLS)
-- ── [2026-11-06] 작업자 자격(worker_skills) · 4M 변경 대장(changes_4m) (Supabase에 적용해 둠 + RLS)
-- ── [2026-11-07] 수정 이력(audit_log + audit_trg 트리거) · 전자 검토·승인(approvals) (Supabase에 적용해 둠)
-- ── [2026-11-07] machines.seq (공정 안 설비 순서)
-- ── [2026-11-07] 부적합 대장(ncr): prod_records 불량 → ncr_sync 트리거로 자동 등록, ncr_guard(승인은 관리자만), audit 트리거, realtime
-- ── [2026-11-07] test_results: ERP 출하검사 첨부 특성 데이터(xlsx/csv)를 Apps Script(MesTestData.gs)가 15분마다 읽어 넣음. insert는 system/admin 역할만
