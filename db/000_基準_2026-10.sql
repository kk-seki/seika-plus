-- 000_基準_2026-10.sql
-- 2026-10-04 時点の本番DB(public)の定義。55番の書き出し結果から自動生成。
-- 新しいDBへ再構築するときに使う。本番では実行しない。
set check_function_bodies = off;

-- ===== シーケンス
create sequence if not exists seika_auth_migration_log_v1200_id_seq;
create sequence if not exists seika_inventory_counts_backup_v1205_id_seq;

-- ===== テーブル
create table if not exists public.app_admins (
  user_id uuid not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.app_settings (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone default now()
);
create table if not exists public.app_state (
  id text not null,
  data jsonb not null,
  updated_at timestamp with time zone not null default now(),
  version bigint not null default 0,
  last_operation_id uuid,
  last_device_meta jsonb not null default '{}'::jsonb,
  last_operation_meta jsonb not null default '{}'::jsonb
);
create table if not exists public.app_state_backup_20260710 (
  id text,
  data jsonb,
  updated_at timestamp with time zone
);
create table if not exists public.app_state_backup_20260721 (
  id text,
  data jsonb,
  updated_at timestamp with time zone
);
create table if not exists public.app_state_backup_blobs_v1167 (
  content_hash text not null,
  snapshot_data jsonb not null,
  data_bytes bigint not null,
  first_seen_at timestamp with time zone not null default clock_timestamp(),
  first_state_id text not null,
  first_state_version text not null
);
create table if not exists public.app_state_backup_migration_audit_v1167 (
  migration_key text not null,
  applied_at timestamp with time zone not null default clock_timestamp(),
  legacy_row_count bigint not null,
  legacy_fingerprint text not null,
  app_state_row_count bigint not null,
  app_state_fingerprint text not null,
  legacy_trigger_definition text not null,
  legacy_function_definition text not null
);
create table if not exists public.app_state_backup_slots_v1167 (
  slot_id bigint not null,
  state_id text not null,
  slot_kind text not null,
  slot_key text not null,
  content_hash text not null,
  state_version text not null,
  snapshot_updated_at timestamp with time zone not null,
  captured_at timestamp with time zone not null default clock_timestamp(),
  captured_by uuid,
  operation_id uuid,
  note text
);
create table if not exists public.app_state_backups (
  backup_id bigint not null,
  state_id text not null,
  state_version bigint,
  state_updated_at timestamp with time zone,
  data jsonb not null,
  last_operation_id uuid,
  last_device_meta jsonb,
  last_operation_meta jsonb,
  backed_up_at timestamp with time zone not null default now()
);
create table if not exists public.inventory (
  item_id text not null,
  current_kg numeric not null default 0,
  updated_by text,
  memo text,
  updated_at timestamp with time zone default now()
);
create table if not exists public.inventory_items (
  id uuid not null default gen_random_uuid(),
  name text not null,
  category text,
  quantity numeric default 0,
  unit text,
  memo text,
  created_at timestamp with time zone default now(),
  qr_enabled boolean default false,
  qr_memo text
);
create table if not exists public.inventory_movements (
  id text not null,
  record_id text,
  item_id text,
  item_name text,
  movement_type text,
  before_total numeric,
  after_total numeric,
  diff_kg numeric,
  user_name text,
  user_role text,
  created_at timestamp with time zone not null default now(),
  data jsonb not null default '{}'::jsonb
);
create table if not exists public.inventory_records (
  id text not null,
  item_id text,
  item_name text,
  kind text,
  total numeric,
  status text,
  user_name text,
  user_role text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  excel_exported_at timestamp with time zone,
  excel_exported_by text,
  data jsonb not null default '{}'::jsonb
);
create table if not exists public.items (
  id text not null,
  name text not null,
  category text,
  unit text not null default 'kg'::text,
  lower_limit numeric default 0,
  upper_limit numeric,
  display_order integer default 0,
  active boolean default true,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);
create table if not exists public.notifications (
  id uuid not null default gen_random_uuid(),
  title text,
  body text not null,
  notification_type text default 'line_copy'::text,
  created_by text,
  created_at timestamp with time zone default now()
);
create table if not exists public.profiles (
  id uuid not null,
  legacy_user_id text not null,
  display_name text not null,
  role text not null,
  active boolean not null default true,
  must_change_password boolean not null default true,
  display_settings jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.purchase_prices (
  id uuid not null default extensions.gen_random_uuid(),
  week_start date not null,
  item_name text not null,
  origin text not null default ''::text,
  supplier text not null default ''::text,
  price_yen_per_kg numeric(12,2) not null,
  tax_type text not null default '税抜'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid not null default auth.uid(),
  updated_by uuid not null default auth.uid(),
  price_type text not null default 'contract'::text
);
create table if not exists public.qr_destinations (
  id uuid not null default gen_random_uuid(),
  name text not null,
  sort_order integer default 0,
  active boolean not null default true,
  memo text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.qr_inventory_sessions (
  session_id uuid not null,
  operation_id uuid not null,
  request_entries jsonb not null,
  room text,
  status text not null default 'confirmed'::text,
  confirmed_at timestamp with time zone not null default now(),
  confirmed_by text,
  cancelled_at timestamp with time zone,
  cancelled_by text,
  cancel_operation_id uuid,
  cancel_request_entries jsonb
);
create table if not exists public.qr_lot_delete_audit_events_v1119 (
  id uuid not null default extensions.gen_random_uuid(),
  deletion_operation_id uuid not null,
  qr_key text not null,
  lot_id text,
  event_type text not null,
  entity_id text,
  before_data jsonb not null default '{}'::jsonb,
  reason text not null,
  performed_at timestamp with time zone not null default now(),
  performed_by uuid not null,
  performed_by_name text not null
);
create table if not exists public.qr_lot_monthly_snapshots (
  target_month date not null,
  lot_id text not null,
  qr_key text,
  lot_no text,
  quantity numeric not null default 0,
  storage_location text,
  deleted boolean not null default false,
  calculated_at timestamp with time zone not null default now()
);
create table if not exists public.qr_lot_movements (
  id uuid not null default gen_random_uuid(),
  occurred_at timestamp with time zone not null default now(),
  movement_type text not null,
  lot_id uuid,
  lot_no text,
  qr_key text,
  item_id text,
  item_name text not null,
  origin text,
  supplier text,
  qty numeric not null default 0,
  unit text default 'kg'::text,
  destination text,
  storage_location text,
  user_id text,
  user_name text,
  memo text,
  excel_exported boolean not null default false,
  excel_exported_month text,
  excel_exported_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  container_type text,
  lot_manage_type text,
  weight numeric,
  before_quantity numeric,
  after_quantity numeric,
  before_weight numeric,
  after_weight numeric,
  weight_status text,
  reason text,
  operation_id uuid,
  reversed_operation_id uuid,
  device_meta jsonb not null default '{}'::jsonb,
  operation_meta jsonb not null default '{}'::jsonb,
  cancelled_at timestamp with time zone,
  cancelled_by text,
  cooperative_name text,
  purchase_price_yen_per_kg numeric(14,2),
  waste_amount_yen numeric(16,2),
  price_match_type text,
  price_match_reason text,
  price_source_supplier text,
  price_average_count integer,
  price_reference_date date,
  price_calculated_at timestamp with time zone
);
create table if not exists public.qr_lot_movements_backup_20260721 (
  id uuid,
  occurred_at timestamp with time zone,
  movement_type text,
  lot_id uuid,
  lot_no text,
  qr_key text,
  item_id text,
  item_name text,
  origin text,
  supplier text,
  qty numeric,
  unit text,
  destination text,
  storage_location text,
  user_id text,
  user_name text,
  memo text,
  excel_exported boolean,
  excel_exported_month text,
  excel_exported_at timestamp with time zone,
  created_at timestamp with time zone,
  container_type text,
  lot_manage_type text,
  weight numeric,
  before_quantity numeric,
  after_quantity numeric,
  before_weight numeric,
  after_weight numeric,
  weight_status text,
  reason text
);
create table if not exists public.qr_lots (
  id uuid not null default gen_random_uuid(),
  lot_no text not null,
  qr_key text not null,
  item_id text,
  item_name text not null,
  origin text,
  supplier text,
  received_date date not null default CURRENT_DATE,
  received_qty numeric not null default 0,
  current_qty numeric not null default 0,
  unit text default 'kg'::text,
  storage_location text,
  status text not null default '在庫あり'::text,
  user_id text,
  user_name text,
  memo text,
  excel_exported boolean not null default false,
  excel_exported_month text,
  excel_exported_at timestamp with time zone,
  active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  container_type text,
  lot_manage_type text default 'normal'::text,
  quantity_label text,
  pack_weight text,
  total_weight numeric,
  current_weight numeric,
  weight_status text default '確定'::text,
  purchase_staff text,
  cooperative_name text,
  purchase_staff_profile_id uuid,
  purchase_staff_legacy_user_id text,
  certification text
);
create table if not exists public.qr_lots_backup_20260721 (
  id uuid,
  lot_no text,
  qr_key text,
  item_id text,
  item_name text,
  origin text,
  supplier text,
  received_date date,
  received_qty numeric,
  current_qty numeric,
  unit text,
  storage_location text,
  status text,
  user_id text,
  user_name text,
  memo text,
  excel_exported boolean,
  excel_exported_month text,
  excel_exported_at timestamp with time zone,
  active boolean,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  container_type text,
  lot_manage_type text,
  quantity_label text,
  pack_weight text,
  total_weight numeric,
  current_weight numeric,
  weight_status text,
  purchase_staff text
);
create table if not exists public.qr_monthly_exports (
  id uuid not null default gen_random_uuid(),
  export_month text not null,
  exported boolean not null default false,
  exported_at timestamp with time zone,
  exported_by text,
  file_name text,
  memo text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.qr_quality_evaluations (
  id uuid not null default gen_random_uuid(),
  qr_key text not null,
  lot_id text,
  lot_no text,
  item_name text,
  grade text not null,
  issues text[] not null default '{}'::text[],
  memo text,
  correction_reason text,
  evaluated_at timestamp with time zone not null default now(),
  evaluated_by uuid not null,
  evaluated_by_name text not null,
  supersedes_id uuid,
  created_at timestamp with time zone not null default now(),
  acknowledged_at timestamp with time zone,
  acknowledged_by uuid,
  acknowledged_by_name text,
  active boolean not null default true,
  invalidated_at timestamp with time zone,
  invalidated_by uuid,
  invalidated_by_name text,
  invalidation_reason text,
  invalidated_by_lot_delete boolean not null default false
);
create table if not exists public.qr_quality_photos (
  id uuid not null default gen_random_uuid(),
  evaluation_id uuid not null,
  storage_path text not null,
  original_name text not null,
  content_type text not null,
  declared_byte_size bigint not null,
  upload_status text not null default 'pending'::text,
  uploaded_by uuid not null,
  created_at timestamp with time zone not null default now(),
  finalized_at timestamp with time zone,
  active boolean not null default true,
  invalidated_at timestamp with time zone,
  invalidated_by uuid,
  invalidated_by_name text,
  invalidation_reason text,
  invalidated_by_lot_delete boolean not null default false
);
create table if not exists public.qr_scan_logs (
  id uuid not null default gen_random_uuid(),
  qr_key text,
  lot_id uuid,
  lot_no text,
  item_id text,
  item_name text,
  action_type text,
  user_id text,
  user_name text,
  device_info text,
  memo text,
  scanned_at timestamp with time zone not null default now()
);
create table if not exists public.qr_settings (
  key text not null,
  value text,
  memo text,
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.qr_storage_locations (
  id uuid not null default gen_random_uuid(),
  name text not null,
  sort_order integer default 0,
  active boolean not null default true,
  memo text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.quality_push_queue_v1144 (
  id uuid not null default gen_random_uuid(),
  evaluation_id uuid not null,
  recipient_profile_id uuid not null,
  subscription_id uuid not null,
  grade text not null,
  payload jsonb not null,
  status text not null default 'pending'::text,
  attempt_count integer not null default 0,
  available_at timestamp with time zone not null default now(),
  lease_until timestamp with time zone,
  locked_at timestamp with time zone,
  locked_by text,
  sent_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.seika_admin_notice_audit_v1150 (
  audit_id bigint not null,
  state_id text not null,
  notice_id text,
  action text not null,
  operation_id text not null,
  actor_id uuid not null,
  actor_role text not null,
  request_hash text not null,
  before_notice jsonb,
  after_notice jsonb,
  expected_version bigint not null,
  resulting_version bigint not null,
  occurred_at timestamp with time zone not null default now()
);
create table if not exists public.seika_admin_notice_operations_v1150 (
  operation_id text not null,
  actor_id uuid not null,
  action text not null,
  request_hash text not null,
  response jsonb not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.seika_admin_notices_v1150 (
  state_id text not null,
  notice_id text not null,
  title text not null,
  body text not null,
  starts_at date,
  ends_at date,
  active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  created_by text not null,
  created_by_id text not null,
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.seika_auth_migration_log_v1200 (
  id bigint not null default nextval('seika_auth_migration_log_v1200_id_seq'::regclass),
  phase text not null,
  func_name text not null,
  func_args text not null,
  revoked_at timestamp with time zone not null default now()
);
create table if not exists public.seika_feature_modes_v1136 (
  feature_key text not null,
  mode text not null,
  updated_at timestamp with time zone not null default now(),
  updated_by uuid,
  update_reason text not null
);
create table if not exists public.seika_feedback_reports (
  id uuid not null default gen_random_uuid(),
  operation_id uuid not null,
  reporter_id uuid not null,
  reporter_legacy_user_id text not null,
  reporter_name text not null,
  reporter_role text not null,
  category text not null,
  title text not null,
  body text not null,
  screen_name text,
  status text not null default 'new'::text,
  admin_memo text not null default ''::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  reviewed_by uuid,
  reviewed_by_name text,
  reviewed_at timestamp with time zone
);
create table if not exists public.seika_fifo_decision_audit_v1136 (
  id uuid not null default extensions.gen_random_uuid(),
  occurred_at timestamp with time zone not null default now(),
  operation_id uuid not null,
  actor_id uuid,
  mode text not null,
  selected_lot_id uuid not null,
  recommended_lot_id uuid,
  selected_rank integer,
  decision text not null,
  violation_reason text,
  override_reason text,
  candidate_snapshot jsonb not null default '[]'::jsonb,
  decision_detail jsonb not null default '{}'::jsonb
);
create table if not exists public.seika_fifo_hold_override_audit_v1136 (
  id uuid not null default extensions.gen_random_uuid(),
  occurred_at timestamp with time zone not null default now(),
  actor_id uuid,
  event_kind text not null,
  lot_id uuid,
  operation_id uuid,
  reason text not null,
  detail jsonb not null default '{}'::jsonb
);
create table if not exists public.seika_fifo_lot_holds_v1136 (
  lot_id uuid not null,
  active boolean not null default true,
  hold_reason text,
  held_at timestamp with time zone,
  held_by uuid,
  released_at timestamp with time zone,
  released_by uuid,
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.seika_fifo_mode_transition_approvals_v1136 (
  id uuid not null default extensions.gen_random_uuid(),
  requested_at timestamp with time zone not null default now(),
  requested_by uuid not null,
  target_mode text not null,
  request_reason text not null,
  requester_confirmed boolean not null,
  required_shadow_audit_count integer not null default 20,
  shadow_audit_count_at_request integer not null,
  active_policy_coverage_ok_at_request boolean not null,
  status text not null default 'pending'::text,
  decided_at timestamp with time zone,
  decided_by uuid,
  decision_reason text,
  approver_confirmed boolean
);
create table if not exists public.seika_fifo_operation_requests_v1136 (
  operation_id uuid not null,
  request_hash text not null,
  request_payload jsonb not null,
  qr_key text not null,
  movement_type text not null,
  lot_id uuid,
  movement_id uuid,
  request_status text not null,
  created_at timestamp with time zone not null default now(),
  completed_at timestamp with time zone,
  actor_id uuid
);
create table if not exists public.seika_inventory_counts_backup_v1205 (
  id bigint not null default nextval('seika_inventory_counts_backup_v1205_id_seq'::regclass),
  backed_at timestamp with time zone not null default now(),
  reason text not null,
  session jsonb not null
);
create table if not exists public.seika_item_aging_policies_v1136 (
  id uuid not null default extensions.gen_random_uuid(),
  item_id text,
  item_name text,
  fifo_enabled boolean not null default true,
  attention_days integer not null default 14,
  warning_days integer not null default 30,
  critical_days integer not null default 60,
  quality_review_requires_confirmation boolean not null default true,
  active boolean not null default true,
  effective_from date not null default CURRENT_DATE,
  effective_to date,
  created_at timestamp with time zone not null default now(),
  created_by uuid not null,
  updated_at timestamp with time zone not null default now(),
  updated_by uuid not null,
  change_reason text not null
);
create table if not exists public.seika_monthly_archives (
  module text not null,
  target_month date not null,
  status text not null default 'pending'::text,
  file_name text,
  row_count bigint not null default 0,
  excel_created_at timestamp with time zone,
  excel_created_by uuid,
  excel_created_by_name text,
  excel_saved_at timestamp with time zone,
  excel_saved_by uuid,
  excel_saved_by_name text,
  deleted_at timestamp with time zone,
  deleted_by uuid,
  deleted_by_name text,
  deleted_count bigint,
  updated_at timestamp with time zone not null default now(),
  photo_count bigint not null default 0,
  deleted_photo_count bigint
);
create table if not exists public.seika_policy_audit_v1136 (
  id uuid not null default extensions.gen_random_uuid(),
  audited_at timestamp with time zone not null default now(),
  audited_by uuid,
  audit_kind text not null,
  subject_key text not null,
  action text not null,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  reason text not null
);
create table if not exists public.seika_policy_backup_v1203 (
  saved_at timestamp with time zone not null default now(),
  schemaname text,
  tablename text,
  policyname text,
  permissive text,
  roles text,
  cmd text,
  qual text,
  with_check text
);
create table if not exists public.seika_qr_operation_requests_v1156 (
  operation_id uuid not null,
  request_payload jsonb not null,
  actor_profile_id uuid not null,
  actor_name text not null,
  actor_role text not null,
  requested_at timestamp with time zone not null default now(),
  completed_at timestamp with time zone,
  result_payload jsonb
);
create table if not exists public.seika_rpc_test_result (
  "項目" text,
  "結果" text
);
create table if not exists public.stock_movements (
  id uuid not null default gen_random_uuid(),
  item_id text,
  movement_type text not null,
  quantity_kg numeric not null default 0,
  before_kg numeric,
  after_kg numeric,
  note text,
  created_by text,
  created_at timestamp with time zone default now()
);
create table if not exists public.trimming_job_cancel_audit_v1144 (
  operation_id uuid not null,
  job_id uuid not null,
  inventory_link_mode text not null,
  reason text not null,
  cancelled_by_profile_id uuid,
  cancelled_at timestamp with time zone not null default now(),
  result jsonb not null
);
create table if not exists public.trimming_job_lots (
  id uuid not null default extensions.gen_random_uuid(),
  trimming_job_id uuid not null,
  qr_lot_id text,
  qr_key text not null,
  lot_no text,
  item_id text,
  item_name text not null,
  origin text not null default ''::text,
  supplier text not null default ''::text,
  usage_mode text not null,
  used_qty numeric(14,4) not null,
  used_weight_kg numeric(14,3) not null,
  unit_weight_kg numeric(14,6),
  before_qty numeric(14,4) not null,
  after_qty numeric(14,4) not null,
  before_weight_kg numeric(14,3),
  after_weight_kg numeric(14,3),
  purchase_price_yen_per_kg numeric(12,2),
  purchase_price_week_start date,
  created_at timestamp with time zone not null default now(),
  price_match_type text,
  price_match_reason text,
  price_source_supplier text,
  price_average_count integer
);
create table if not exists public.trimming_job_outputs (
  id uuid not null default extensions.gen_random_uuid(),
  trimming_job_id uuid not null,
  item_id text,
  item_name text not null,
  output_weight_kg numeric(14,3) not null,
  output_qty numeric(14,4),
  unit_weight_kg numeric(14,6),
  mode text not null,
  apply_to_normal_inventory boolean not null default false,
  normal_inventory_record_id text,
  normal_inventory_movement_id text,
  normal_before_total_kg numeric(14,3),
  normal_after_total_kg numeric(14,3),
  created_at timestamp with time zone not null default now()
);
create table if not exists public.trimming_jobs (
  id uuid not null default extensions.gen_random_uuid(),
  operation_id uuid not null,
  work_date date not null default CURRENT_DATE,
  week_start date not null,
  source_item_id text,
  source_item_name text not null,
  input_weight_kg numeric(14,3) not null,
  output_weight_kg numeric(14,3) not null default 0,
  loss_weight_kg numeric(14,3) not null default 0,
  yield_percent numeric(8,3) not null default 0,
  purchase_price_yen_per_kg numeric(12,2),
  input_cost_yen numeric(14,2),
  note text not null default ''::text,
  created_at timestamp with time zone not null default now(),
  created_by uuid not null default auth.uid(),
  created_by_name text not null default ''::text,
  updated_at timestamp with time zone not null default now(),
  price_match_summary text,
  inventory_link_mode text not null default 'legacy'::text
);
create table if not exists public.user_admin_audit_logs (
  id bigint not null,
  actor_id uuid not null,
  actor_legacy_user_id text not null,
  actor_display_name text not null,
  action text not null,
  target_id uuid not null,
  target_legacy_user_id text not null,
  target_display_name text not null,
  before_data jsonb not null default '{}'::jsonb,
  after_data jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.waste_records (
  id text not null,
  waste_date date,
  item_name text,
  qty numeric,
  unit_price numeric,
  amount numeric,
  user_name text,
  user_id text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  excel_exported_at timestamp with time zone,
  excel_exported_by text,
  data jsonb not null default '{}'::jsonb
);
create table if not exists public.web_push_subscriptions_v1144 (
  id uuid not null default gen_random_uuid(),
  profile_id uuid not null,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  user_agent text,
  device_label text,
  active boolean not null default true,
  failure_count integer not null default 0,
  last_success_at timestamp with time zone,
  last_failure_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- ===== 制約（外部キー以外）
alter table public.app_admins add constraint app_admins_pkey PRIMARY KEY (user_id);
alter table public.app_settings add constraint app_settings_pkey PRIMARY KEY (key);
alter table public.app_state_backup_blobs_v1167 add constraint app_state_backup_blobs_v1167_content_hash_check CHECK ((content_hash ~ '^[0-9a-f]{64}$'::text));
alter table public.app_state_backup_blobs_v1167 add constraint app_state_backup_blobs_v1167_data_bytes_check CHECK ((data_bytes >= 0));
alter table public.app_state_backup_blobs_v1167 add constraint app_state_backup_blobs_v1167_pkey PRIMARY KEY (content_hash);
alter table public.app_state_backup_migration_audit_v1167 add constraint app_state_backup_migration_audit_v1_app_state_fingerprint_check CHECK ((app_state_fingerprint ~ '^[0-9a-f]{64}$'::text));
alter table public.app_state_backup_migration_audit_v1167 add constraint app_state_backup_migration_audit_v1167_legacy_fingerprint_check CHECK ((legacy_fingerprint ~ '^[0-9a-f]{64}$'::text));
alter table public.app_state_backup_migration_audit_v1167 add constraint app_state_backup_migration_audit_v1167_migration_key_check CHECK ((migration_key = 'first_stage'::text));
alter table public.app_state_backup_migration_audit_v1167 add constraint app_state_backup_migration_audit_v1167_pkey PRIMARY KEY (migration_key);
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_manual_operation_ck CHECK (((slot_kind = 'manual'::text) = (operation_id IS NOT NULL)));
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_manual_operation_uq UNIQUE (slot_kind, operation_id);
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_note_check CHECK (((note IS NULL) OR (length(note) <= 500)));
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_pkey PRIMARY KEY (slot_id);
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_slot_kind_check CHECK ((slot_kind = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text, 'manual'::text])));
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_state_slot_uq UNIQUE (state_id, slot_kind, slot_key);
alter table public.app_state_backups add constraint app_state_backups_pkey PRIMARY KEY (backup_id);
alter table public.app_state add constraint app_state_pkey PRIMARY KEY (id);
alter table public.inventory_items add constraint inventory_items_pkey PRIMARY KEY (id);
alter table public.inventory_movements add constraint inventory_movements_pkey PRIMARY KEY (id);
alter table public.inventory_records add constraint inventory_records_pkey PRIMARY KEY (id);
alter table public.inventory add constraint inventory_pkey PRIMARY KEY (item_id);
alter table public.items add constraint items_pkey PRIMARY KEY (id);
alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_legacy_user_id_key UNIQUE (legacy_user_id);
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'worker'::text, 'buyer'::text, 'sales'::text, 'clerk'::text, 'office_viewer'::text, 'viewer'::text])));
alter table public.purchase_prices add constraint purchase_prices_item_name_check CHECK ((btrim(item_name) <> ''::text));
alter table public.purchase_prices add constraint purchase_prices_pkey PRIMARY KEY (id);
alter table public.purchase_prices add constraint purchase_prices_price_type_check CHECK ((price_type = ANY (ARRAY['market'::text, 'contract'::text])));
alter table public.purchase_prices add constraint purchase_prices_price_yen_per_kg_check CHECK ((price_yen_per_kg >= (0)::numeric));
alter table public.purchase_prices add constraint purchase_prices_tax_type_check CHECK ((tax_type = '税抜'::text));
alter table public.purchase_prices add constraint purchase_prices_week_is_monday CHECK ((EXTRACT(isodow FROM week_start) = (1)::numeric));
alter table public.purchase_prices add constraint purchase_prices_week_item_origin_supplier_key UNIQUE (week_start, item_name, origin, supplier);
alter table public.qr_destinations add constraint qr_destinations_name_key UNIQUE (name);
alter table public.qr_destinations add constraint qr_destinations_pkey PRIMARY KEY (id);
alter table public.qr_inventory_sessions add constraint qr_inventory_sessions_cancel_operation_id_key UNIQUE (cancel_operation_id);
alter table public.qr_inventory_sessions add constraint qr_inventory_sessions_operation_id_key UNIQUE (operation_id);
alter table public.qr_inventory_sessions add constraint qr_inventory_sessions_pkey PRIMARY KEY (session_id);
alter table public.qr_inventory_sessions add constraint qr_inventory_sessions_room_check CHECK (((room IS NULL) OR (room = ANY (ARRAY['room2'::text, 'room3'::text]))));
alter table public.qr_inventory_sessions add constraint qr_inventory_sessions_status_check CHECK ((status = ANY (ARRAY['confirmed'::text, 'cancelled'::text])));
alter table public.qr_lot_delete_audit_events_v1119 add constraint qr_lot_delete_audit_events_v1119_event_type_check CHECK ((event_type = ANY (ARRAY['lot_soft_deleted'::text, 'quality_evaluation_invalidated'::text, 'quality_photo_invalidated'::text])));
alter table public.qr_lot_delete_audit_events_v1119 add constraint qr_lot_delete_audit_events_v1119_pkey PRIMARY KEY (id);
alter table public.qr_lot_monthly_snapshots add constraint qr_lot_monthly_snapshots_pkey PRIMARY KEY (target_month, lot_id);
alter table public.qr_lot_monthly_snapshots add constraint qr_lot_monthly_snapshots_target_month_check CHECK ((target_month = (date_trunc('month'::text, (target_month)::timestamp with time zone))::date));
alter table public.qr_lot_movements add constraint qr_lot_movements_movement_type_check CHECK ((movement_type = ANY (ARRAY['棚卸し調整増'::text, '棚卸し調整減'::text, '入庫'::text, '出庫'::text, '廃棄'::text, '出庫・調整減'::text, '入庫・調整増'::text, '差分なし'::text, '調整'::text, '重量確定'::text, '重量更新'::text, 'ロット情報訂正'::text])));
alter table public.qr_lot_movements add constraint qr_lot_movements_pkey PRIMARY KEY (id);
alter table public.qr_lots add constraint qr_lots_lot_no_key UNIQUE (lot_no);
alter table public.qr_lots add constraint qr_lots_pkey PRIMARY KEY (id);
alter table public.qr_lots add constraint qr_lots_qr_key_key UNIQUE (qr_key);
alter table public.qr_lots add constraint qr_lots_status_check CHECK ((status = ANY (ARRAY['在庫あり'::text, '在庫なし'::text, '削除'::text])));
alter table public.qr_monthly_exports add constraint qr_monthly_exports_export_month_key UNIQUE (export_month);
alter table public.qr_monthly_exports add constraint qr_monthly_exports_pkey PRIMARY KEY (id);
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_correction_size CHECK ((char_length(COALESCE(correction_reason, ''::text)) <= 500));
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_grade_check CHECK ((grade = ANY (ARRAY['good'::text, 'review'::text, 'bad'::text])));
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_issue_count CHECK ((cardinality(issues) <= 12));
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_memo_size CHECK ((char_length(COALESCE(memo, ''::text)) <= 1000));
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_no_self_supersede CHECK (((supersedes_id IS NULL) OR (supersedes_id <> id)));
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_pkey PRIMARY KEY (id);
alter table public.qr_quality_photos add constraint qr_quality_photos_content_type_check CHECK ((content_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text])));
alter table public.qr_quality_photos add constraint qr_quality_photos_declared_byte_size_check CHECK (((declared_byte_size > 0) AND (declared_byte_size <= 512000)));
alter table public.qr_quality_photos add constraint qr_quality_photos_path_format CHECK ((storage_path ~ '^evaluations/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'::text));
alter table public.qr_quality_photos add constraint qr_quality_photos_pkey PRIMARY KEY (id);
alter table public.qr_quality_photos add constraint qr_quality_photos_storage_path_key UNIQUE (storage_path);
alter table public.qr_quality_photos add constraint qr_quality_photos_upload_status_check CHECK ((upload_status = ANY (ARRAY['pending'::text, 'finalized'::text])));
alter table public.qr_scan_logs add constraint qr_scan_logs_pkey PRIMARY KEY (id);
alter table public.qr_settings add constraint qr_settings_pkey PRIMARY KEY (key);
alter table public.qr_storage_locations add constraint qr_storage_locations_name_key UNIQUE (name);
alter table public.qr_storage_locations add constraint qr_storage_locations_pkey PRIMARY KEY (id);
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_attempt_count_check CHECK ((attempt_count >= 0));
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_evaluation_subscription_key UNIQUE (evaluation_id, subscription_id);
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_grade_check CHECK ((grade = ANY (ARRAY['review'::text, 'bad'::text])));
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_pkey PRIMARY KEY (id);
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'retry'::text, 'sent'::text, 'cancelled'::text, 'dead'::text])));
alter table public.seika_admin_notice_audit_v1150 add constraint seika_admin_notice_audit_v1150_action_check CHECK ((action = ANY (ARRAY['create'::text, 'set_active'::text, 'delete'::text])));
alter table public.seika_admin_notice_audit_v1150 add constraint seika_admin_notice_audit_v1150_operation_length CHECK (((char_length(operation_id) >= 1) AND (char_length(operation_id) <= 200)));
alter table public.seika_admin_notice_audit_v1150 add constraint seika_admin_notice_audit_v1150_pkey PRIMARY KEY (audit_id);
alter table public.seika_admin_notice_operations_v1150 add constraint seika_admin_notice_operations_v1150_action_check CHECK ((action = ANY (ARRAY['create'::text, 'set_active'::text, 'delete'::text])));
alter table public.seika_admin_notice_operations_v1150 add constraint seika_admin_notice_operations_v1150_id_length CHECK (((char_length(operation_id) >= 1) AND (char_length(operation_id) <= 200)));
alter table public.seika_admin_notice_operations_v1150 add constraint seika_admin_notice_operations_v1150_pkey PRIMARY KEY (operation_id);
alter table public.seika_admin_notices_v1150 add constraint seika_admin_notices_v1150_body_nonempty CHECK (((char_length(btrim(body)) >= 1) AND (char_length(btrim(body)) <= 1000)));
alter table public.seika_admin_notices_v1150 add constraint seika_admin_notices_v1150_id_length CHECK (((char_length(notice_id) >= 1) AND (char_length(notice_id) <= 200)));
alter table public.seika_admin_notices_v1150 add constraint seika_admin_notices_v1150_period CHECK (((starts_at IS NULL) OR (ends_at IS NULL) OR (starts_at <= ends_at)));
alter table public.seika_admin_notices_v1150 add constraint seika_admin_notices_v1150_pkey PRIMARY KEY (state_id, notice_id);
alter table public.seika_admin_notices_v1150 add constraint seika_admin_notices_v1150_title_nonempty CHECK (((char_length(btrim(title)) >= 1) AND (char_length(btrim(title)) <= 100)));
alter table public.seika_auth_migration_log_v1200 add constraint seika_auth_migration_log_v1200_pkey PRIMARY KEY (id);
alter table public.seika_feature_modes_v1136 add constraint seika_feature_modes_v1136_feature_key_check CHECK ((feature_key = 'smart_fifo'::text));
alter table public.seika_feature_modes_v1136 add constraint seika_feature_modes_v1136_mode_check CHECK ((mode = ANY (ARRAY['disabled'::text, 'shadow'::text, 'warn'::text, 'enforce'::text])));
alter table public.seika_feature_modes_v1136 add constraint seika_feature_modes_v1136_pkey PRIMARY KEY (feature_key);
alter table public.seika_feature_modes_v1136 add constraint seika_feature_modes_v1136_update_reason_check CHECK (((char_length(btrim(update_reason)) >= 1) AND (char_length(btrim(update_reason)) <= 500)));
alter table public.seika_feedback_reports add constraint seika_feedback_reports_admin_memo_check CHECK ((char_length(admin_memo) <= 500));
alter table public.seika_feedback_reports add constraint seika_feedback_reports_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 2000)));
alter table public.seika_feedback_reports add constraint seika_feedback_reports_category_check CHECK ((category = ANY (ARRAY['不具合'::text, '操作質問'::text, '改善提案'::text, 'その他'::text])));
alter table public.seika_feedback_reports add constraint seika_feedback_reports_operation_id_key UNIQUE (operation_id);
alter table public.seika_feedback_reports add constraint seika_feedback_reports_pkey PRIMARY KEY (id);
alter table public.seika_feedback_reports add constraint seika_feedback_reports_status_check CHECK ((status = ANY (ARRAY['new'::text, 'reviewing'::text, 'planned'::text, 'done'::text])));
alter table public.seika_feedback_reports add constraint seika_feedback_reports_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 100)));
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_check CHECK (((char_length(COALESCE(violation_reason, ''::text)) <= 500) AND (char_length(COALESCE(override_reason, ''::text)) <= 500)));
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_decision_check CHECK ((decision = ANY (ARRAY['not_applicable'::text, 'recommended'::text, 'violation'::text, 'override'::text, 'candidate_unavailable'::text])));
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_mode_check CHECK ((mode = ANY (ARRAY['disabled'::text, 'shadow'::text, 'warn'::text, 'enforce'::text])));
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_operation_id_key UNIQUE (operation_id);
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_pkey PRIMARY KEY (id);
alter table public.seika_fifo_hold_override_audit_v1136 add constraint seika_fifo_hold_override_audit_v1136_event_kind_check CHECK ((event_kind = ANY (ARRAY['hold'::text, 'release'::text, 'override'::text])));
alter table public.seika_fifo_hold_override_audit_v1136 add constraint seika_fifo_hold_override_audit_v1136_pkey PRIMARY KEY (id);
alter table public.seika_fifo_hold_override_audit_v1136 add constraint seika_fifo_hold_override_audit_v1136_reason_check CHECK (((char_length(btrim(reason)) >= 1) AND (char_length(btrim(reason)) <= 500)));
alter table public.seika_fifo_lot_holds_v1136 add constraint seika_fifo_lot_holds_v1136_check CHECK (((active AND (held_at IS NOT NULL) AND (held_by IS NOT NULL) AND (released_at IS NULL) AND (released_by IS NULL) AND ((char_length(btrim(COALESCE(hold_reason, ''::text))) >= 1) AND (char_length(btrim(COALESCE(hold_reason, ''::text))) <= 500))) OR ((NOT active) AND (held_at IS NOT NULL) AND (held_by IS NOT NULL) AND (released_at IS NOT NULL) AND (released_by IS NOT NULL))));
alter table public.seika_fifo_lot_holds_v1136 add constraint seika_fifo_lot_holds_v1136_pkey PRIMARY KEY (lot_id);
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_ap_required_shadow_audit_count_check CHECK ((required_shadow_audit_count >= 1));
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_check CHECK ((((status = 'pending'::text) AND (decided_at IS NULL) AND (decided_by IS NULL)) OR ((status = ANY (ARRAY['approved'::text, 'rejected'::text, 'superseded'::text])) AND (decided_at IS NOT NULL) AND (decided_by IS NOT NULL) AND ((char_length(btrim(COALESCE(decision_reason, ''::text))) >= 1) AND (char_length(btrim(COALESCE(decision_reason, ''::text))) <= 500)))));
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_pkey PRIMARY KEY (id);
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_request_reason_check CHECK (((char_length(btrim(request_reason)) >= 1) AND (char_length(btrim(request_reason)) <= 500)));
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_target_mode_check CHECK ((target_mode = ANY (ARRAY['warn'::text, 'enforce'::text])));
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_check CHECK ((((request_status = 'completed'::text) AND (lot_id IS NOT NULL) AND (movement_id IS NOT NULL) AND (completed_at IS NOT NULL)) OR (request_status = 'conflict'::text)));
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_movement_type_check CHECK ((movement_type = '出庫'::text));
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_pkey PRIMARY KEY (operation_id);
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_request_hash_check CHECK ((request_hash ~ '^[0-9a-f]{32}$'::text));
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_request_status_check CHECK ((request_status = ANY (ARRAY['completed'::text, 'conflict'::text])));
alter table public.seika_inventory_counts_backup_v1205 add constraint seika_inventory_counts_backup_v1205_pkey PRIMARY KEY (id);
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_change_reason_check CHECK (((char_length(btrim(change_reason)) >= 1) AND (char_length(btrim(change_reason)) <= 500)));
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_check CHECK (((NULLIF(btrim(COALESCE(item_id, ''::text)), ''::text) IS NOT NULL) OR (NULLIF(btrim(COALESCE(item_name, ''::text)), ''::text) IS NOT NULL)));
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_check1 CHECK (((attention_days >= 0) AND (warning_days >= attention_days) AND (critical_days >= warning_days)));
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_check2 CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)));
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_pkey PRIMARY KEY (id);
alter table public.seika_monthly_archives add constraint seika_monthly_archives_module_check CHECK ((module = ANY (ARRAY['waste'::text, 'qr'::text, 'quality'::text])));
alter table public.seika_monthly_archives add constraint seika_monthly_archives_pkey PRIMARY KEY (module, target_month);
alter table public.seika_monthly_archives add constraint seika_monthly_archives_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'excel_created'::text, 'excel_saved'::text, 'deleting'::text, 'deleted'::text])));
alter table public.seika_monthly_archives add constraint seika_monthly_archives_target_month_check CHECK ((target_month = (date_trunc('month'::text, (target_month)::timestamp with time zone))::date));
alter table public.seika_policy_audit_v1136 add constraint seika_policy_audit_v1136_action_check CHECK ((action = ANY (ARRAY['create'::text, 'update'::text, 'deactivate'::text, 'mode_change'::text, 'request'::text, 'approve'::text, 'reject'::text])));
alter table public.seika_policy_audit_v1136 add constraint seika_policy_audit_v1136_audit_kind_check CHECK ((audit_kind = ANY (ARRAY['feature_mode'::text, 'aging_policy'::text, 'mode_transition'::text])));
alter table public.seika_policy_audit_v1136 add constraint seika_policy_audit_v1136_pkey PRIMARY KEY (id);
alter table public.seika_policy_audit_v1136 add constraint seika_policy_audit_v1136_reason_check CHECK (((char_length(btrim(reason)) >= 1) AND (char_length(btrim(reason)) <= 500)));
alter table public.seika_qr_operation_requests_v1156 add constraint seika_qr_operation_requests_v1156_payload_object CHECK ((jsonb_typeof(request_payload) = 'object'::text));
alter table public.seika_qr_operation_requests_v1156 add constraint seika_qr_operation_requests_v1156_pkey PRIMARY KEY (operation_id);
alter table public.seika_qr_operation_requests_v1156 add constraint seika_qr_operation_requests_v1156_result_object CHECK (((result_payload IS NULL) OR (jsonb_typeof(result_payload) = 'object'::text)));
alter table public.stock_movements add constraint stock_movements_movement_type_check CHECK ((movement_type = ANY (ARRAY['stocktake'::text, 'in'::text, 'out'::text, 'adjust'::text])));
alter table public.stock_movements add constraint stock_movements_pkey PRIMARY KEY (id);
alter table public.trimming_job_cancel_audit_v1144 add constraint trimming_job_cancel_audit_v1144_mode_check CHECK ((inventory_link_mode = 'none'::text));
alter table public.trimming_job_cancel_audit_v1144 add constraint trimming_job_cancel_audit_v1144_pkey PRIMARY KEY (operation_id);
alter table public.trimming_job_cancel_audit_v1144 add constraint trimming_job_cancel_audit_v1144_reason_check CHECK ((((char_length(btrim(reason)) >= 1) AND (char_length(btrim(reason)) <= 500)) AND (reason !~ '[[:cntrl:]]'::text)));
alter table public.trimming_job_lots add constraint trimming_job_lots_after_qty_check CHECK ((after_qty >= (0)::numeric));
alter table public.trimming_job_lots add constraint trimming_job_lots_job_qr_key_key UNIQUE (trimming_job_id, qr_key);
alter table public.trimming_job_lots add constraint trimming_job_lots_pkey PRIMARY KEY (id);
alter table public.trimming_job_lots add constraint trimming_job_lots_usage_mode_check CHECK ((usage_mode = ANY (ARRAY['qty'::text, 'weight'::text])));
alter table public.trimming_job_lots add constraint trimming_job_lots_used_qty_check CHECK ((used_qty > (0)::numeric));
alter table public.trimming_job_lots add constraint trimming_job_lots_used_weight_kg_check CHECK ((used_weight_kg > (0)::numeric));
alter table public.trimming_job_outputs add constraint trimming_job_outputs_item_name_check CHECK ((btrim(item_name) <> ''::text));
alter table public.trimming_job_outputs add constraint trimming_job_outputs_mode_check CHECK ((mode = ANY (ARRAY['weight'::text, 'qty'::text])));
alter table public.trimming_job_outputs add constraint trimming_job_outputs_mode_values CHECK ((((mode = 'weight'::text) AND (output_qty IS NULL) AND (unit_weight_kg IS NULL)) OR ((mode = 'qty'::text) AND (output_qty > (0)::numeric) AND (unit_weight_kg > (0)::numeric))));
alter table public.trimming_job_outputs add constraint trimming_job_outputs_output_weight_kg_check CHECK ((output_weight_kg > (0)::numeric));
alter table public.trimming_job_outputs add constraint trimming_job_outputs_pkey PRIMARY KEY (id);
alter table public.trimming_jobs add constraint trimming_jobs_input_weight_kg_check CHECK ((input_weight_kg > (0)::numeric));
alter table public.trimming_jobs add constraint trimming_jobs_inventory_link_mode_check CHECK ((inventory_link_mode = ANY (ARRAY['legacy'::text, 'none'::text])));
alter table public.trimming_jobs add constraint trimming_jobs_loss_weight_kg_check CHECK ((loss_weight_kg >= (('-1'::integer)::numeric * GREATEST(input_weight_kg, (0)::numeric))));
alter table public.trimming_jobs add constraint trimming_jobs_operation_id_key UNIQUE (operation_id);
alter table public.trimming_jobs add constraint trimming_jobs_output_weight_kg_check CHECK ((output_weight_kg >= (0)::numeric));
alter table public.trimming_jobs add constraint trimming_jobs_pkey PRIMARY KEY (id);
alter table public.trimming_jobs add constraint trimming_jobs_week_is_monday CHECK ((EXTRACT(isodow FROM week_start) = (1)::numeric));
alter table public.trimming_jobs add constraint trimming_jobs_weight_balance CHECK ((abs(((input_weight_kg - output_weight_kg) - loss_weight_kg)) <= 0.011));
alter table public.trimming_jobs add constraint trimming_jobs_yield_percent_check CHECK (((yield_percent >= (0)::numeric) AND (yield_percent <= (1000)::numeric)));
alter table public.user_admin_audit_logs add constraint user_admin_audit_logs_action_check CHECK ((action = ANY (ARRAY['create'::text, 'update'::text, 'deactivate'::text, 'activate'::text, 'reset_password'::text])));
alter table public.user_admin_audit_logs add constraint user_admin_audit_logs_pkey PRIMARY KEY (id);
alter table public.waste_records add constraint waste_records_pkey PRIMARY KEY (id);
alter table public.web_push_subscriptions_v1144 add constraint web_push_subscriptions_v1144_endpoint_key UNIQUE (endpoint);
alter table public.web_push_subscriptions_v1144 add constraint web_push_subscriptions_v1144_failure_count_check CHECK ((failure_count >= 0));
alter table public.web_push_subscriptions_v1144 add constraint web_push_subscriptions_v1144_pkey PRIMARY KEY (id);

-- ===== 索引
CREATE INDEX app_state_backup_slots_v1167_captured_at_idx ON public.app_state_backup_slots_v1167 USING btree (captured_at DESC);
CREATE INDEX app_state_backup_slots_v1167_hash_idx ON public.app_state_backup_slots_v1167 USING btree (content_hash);
CREATE INDEX app_state_backups_state_time_idx ON public.app_state_backups USING btree (state_id, backed_up_at DESC);
CREATE INDEX idx_qr_lot_movements_excel_exported ON public.qr_lot_movements USING btree (excel_exported);
CREATE INDEX idx_qr_lot_movements_lot_id ON public.qr_lot_movements USING btree (lot_id);
CREATE INDEX idx_qr_lot_movements_occurred_at ON public.qr_lot_movements USING btree (occurred_at);
CREATE INDEX idx_qr_lot_movements_qr_key ON public.qr_lot_movements USING btree (qr_key);
CREATE INDEX idx_qr_lots_active ON public.qr_lots USING btree (active);
CREATE INDEX idx_qr_lots_excel_exported ON public.qr_lots USING btree (excel_exported);
CREATE INDEX idx_qr_lots_item_id ON public.qr_lots USING btree (item_id);
CREATE INDEX idx_qr_lots_item_name ON public.qr_lots USING btree (item_name);
CREATE INDEX idx_qr_lots_lot_no ON public.qr_lots USING btree (lot_no);
CREATE INDEX idx_qr_lots_qr_key ON public.qr_lots USING btree (qr_key);
CREATE INDEX idx_qr_lots_received_date ON public.qr_lots USING btree (received_date);
CREATE INDEX idx_qr_lots_status ON public.qr_lots USING btree (status);
CREATE INDEX idx_qr_movements_excel_exported ON public.qr_lot_movements USING btree (excel_exported);
CREATE INDEX idx_qr_movements_item_id ON public.qr_lot_movements USING btree (item_id);
CREATE INDEX idx_qr_movements_lot_no ON public.qr_lot_movements USING btree (lot_no);
CREATE INDEX idx_qr_movements_occurred_at ON public.qr_lot_movements USING btree (occurred_at);
CREATE INDEX idx_qr_movements_type ON public.qr_lot_movements USING btree (movement_type);
CREATE INDEX idx_qr_scan_logs_scanned_at ON public.qr_scan_logs USING btree (scanned_at);
CREATE INDEX inventory_movements_created_at_idx ON public.inventory_movements USING btree (created_at);
CREATE INDEX inventory_movements_item_id_idx ON public.inventory_movements USING btree (item_id);
CREATE INDEX inventory_movements_record_id_idx ON public.inventory_movements USING btree (record_id);
CREATE INDEX inventory_movements_type_idx ON public.inventory_movements USING btree (movement_type);
CREATE INDEX inventory_records_created_at_idx ON public.inventory_records USING btree (created_at);
CREATE INDEX inventory_records_item_id_idx ON public.inventory_records USING btree (item_id);
CREATE INDEX inventory_records_status_idx ON public.inventory_records USING btree (status);
CREATE INDEX purchase_prices_lookup_idx ON public.purchase_prices USING btree (week_start DESC, item_name, origin, supplier);
CREATE INDEX qr_lot_delete_audit_events_v1119_key_idx ON public.qr_lot_delete_audit_events_v1119 USING btree (qr_key, performed_at DESC);
CREATE INDEX qr_lot_delete_audit_events_v1119_operation_idx ON public.qr_lot_delete_audit_events_v1119 USING btree (deletion_operation_id);
CREATE INDEX qr_lot_monthly_snapshots_qr_idx ON public.qr_lot_monthly_snapshots USING btree (qr_key, target_month DESC);
CREATE INDEX qr_lot_movements_lot_id_created_at_idx ON public.qr_lot_movements USING btree (lot_id, created_at DESC);
CREATE UNIQUE INDEX qr_lot_movements_operation_id_uidx ON public.qr_lot_movements USING btree (operation_id) WHERE (operation_id IS NOT NULL);
CREATE UNIQUE INDEX qr_lot_movements_operation_id_uq ON public.qr_lot_movements USING btree (operation_id) WHERE (operation_id IS NOT NULL);
CREATE UNIQUE INDEX qr_lot_movements_reversed_operation_id_uq ON public.qr_lot_movements USING btree (reversed_operation_id) WHERE (reversed_operation_id IS NOT NULL);
CREATE INDEX qr_lots_purchase_staff_legacy_user_id_idx ON public.qr_lots USING btree (purchase_staff_legacy_user_id) WHERE (NULLIF(btrim(purchase_staff_legacy_user_id), ''::text) IS NOT NULL);
CREATE INDEX qr_lots_purchase_staff_profile_id_idx ON public.qr_lots USING btree (purchase_staff_profile_id) WHERE (purchase_staff_profile_id IS NOT NULL);
CREATE INDEX qr_quality_evaluations_active_qr_key_idx ON public.qr_quality_evaluations USING btree (qr_key, evaluated_at DESC) WHERE active;
CREATE INDEX qr_quality_evaluations_low_unacknowledged_v1103_idx ON public.qr_quality_evaluations USING btree (grade, evaluated_at DESC, created_at DESC) WHERE ((grade = ANY (ARRAY['review'::text, 'bad'::text])) AND (acknowledged_at IS NULL));
CREATE UNIQUE INDEX qr_quality_evaluations_one_replacement_idx ON public.qr_quality_evaluations USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);
CREATE INDEX qr_quality_evaluations_qr_key_idx ON public.qr_quality_evaluations USING btree (qr_key, evaluated_at DESC, created_at DESC);
CREATE INDEX qr_quality_photos_active_evaluation_idx ON public.qr_quality_photos USING btree (evaluation_id, created_at) WHERE active;
CREATE INDEX qr_quality_photos_evaluation_idx ON public.qr_quality_photos USING btree (evaluation_id, created_at);
CREATE INDEX quality_push_queue_v1144_claim_idx ON public.quality_push_queue_v1144 USING btree (status, available_at, created_at);
CREATE INDEX seika_admin_notice_audit_v1150_notice_time_idx ON public.seika_admin_notice_audit_v1150 USING btree (state_id, notice_id, occurred_at DESC);
CREATE INDEX seika_admin_notice_audit_v1150_state_time_idx ON public.seika_admin_notice_audit_v1150 USING btree (state_id, occurred_at DESC);
CREATE INDEX seika_admin_notice_operations_v1150_actor_time_idx ON public.seika_admin_notice_operations_v1150 USING btree (actor_id, created_at DESC);
CREATE INDEX seika_admin_notices_v1150_active_idx ON public.seika_admin_notices_v1150 USING btree (state_id, active, starts_at, ends_at, created_at DESC);
CREATE INDEX seika_feedback_reports_status_created_idx ON public.seika_feedback_reports USING btree (status, created_at DESC);
CREATE INDEX seika_fifo_decision_audit_v1136_occurred_idx ON public.seika_fifo_decision_audit_v1136 USING btree (occurred_at DESC);
CREATE INDEX seika_fifo_hold_override_audit_v1136_lot_idx ON public.seika_fifo_hold_override_audit_v1136 USING btree (lot_id, occurred_at DESC);
CREATE UNIQUE INDEX seika_fifo_mode_transition_one_pending_uidx ON public.seika_fifo_mode_transition_approvals_v1136 USING btree ((1)) WHERE (status = 'pending'::text);
CREATE INDEX seika_fifo_operation_requests_v1136_created_idx ON public.seika_fifo_operation_requests_v1136 USING btree (created_at DESC);
CREATE UNIQUE INDEX seika_item_aging_policies_v1136_current_uidx ON public.seika_item_aging_policies_v1136 USING btree (COALESCE(NULLIF(btrim(item_id), ''::text), '∅'::text), COALESCE(NULLIF(btrim(item_name), ''::text), '∅'::text)) WHERE (active AND (effective_to IS NULL));
CREATE INDEX seika_item_aging_policies_v1136_lookup_idx ON public.seika_item_aging_policies_v1136 USING btree (item_id, item_name, active, effective_from DESC);
CREATE INDEX seika_monthly_archives_status_idx ON public.seika_monthly_archives USING btree (module, status, target_month);
CREATE INDEX trimming_job_lots_qr_key_idx ON public.trimming_job_lots USING btree (qr_key);
CREATE INDEX trimming_job_outputs_item_idx ON public.trimming_job_outputs USING btree (item_name);
CREATE INDEX trimming_jobs_work_date_idx ON public.trimming_jobs USING btree (work_date DESC);
CREATE INDEX user_admin_audit_logs_created_at_idx ON public.user_admin_audit_logs USING btree (created_at DESC);
CREATE INDEX waste_records_created_at_idx ON public.waste_records USING btree (created_at);
CREATE INDEX waste_records_item_name_idx ON public.waste_records USING btree (item_name);
CREATE INDEX waste_records_waste_date_idx ON public.waste_records USING btree (waste_date);
CREATE INDEX web_push_subscriptions_v1144_active_profile_idx ON public.web_push_subscriptions_v1144 USING btree (profile_id) WHERE active;

-- ===== 関数
CREATE OR REPLACE FUNCTION public.acknowledge_qr_quality_evaluation_v1103(p_evaluation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_evaluation public.qr_quality_evaluations%rowtype;
  v_lot_id uuid;
  v_context jsonb;
  v_already boolean;
begin
  select p.* into v_profile from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if not found or v_profile.role not in ('admin','buyer') then raise exception '低評価確認の権限がありません' using errcode='42501'; end if;
  if p_evaluation_id is null then raise exception '品質評価IDが必要です' using errcode='22023'; end if;
  select * into v_evaluation from public.qr_quality_evaluations e
  where e.id=p_evaluation_id and coalesce(e.active,true)=true and to_jsonb(e)->>'invalidated_at' is null and coalesce((to_jsonb(e)->>'invalidated_by_lot_delete')::boolean,false)=false
  for update;
  if not found then raise exception '有効な品質評価が見つかりません' using errcode='P0002'; end if;
  if v_evaluation.grade not in ('review','bad') then raise exception '良好評価は確認済みにできません' using errcode='22023'; end if;
  if exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=v_evaluation.id and coalesce(n.active,true)=true and to_jsonb(n)->>'invalidated_at' is null and coalesce((to_jsonb(n)->>'invalidated_by_lot_delete')::boolean,false)=false) then raise exception '訂正前の評価は確認できません。最新評価を確認してください' using errcode='22023'; end if;

  if v_profile.role='buyer' then
    select q.id into v_lot_id from public.qr_lots q
    where (v_evaluation.lot_id is not null and q.id::text=v_evaluation.lot_id::text) or q.qr_key=v_evaluation.qr_key
    order by case when v_evaluation.lot_id is not null and q.id::text=v_evaluation.lot_id::text then 0 else 1 end,coalesce(q.active,true) desc,q.created_at desc,q.id desc limit 1;
    if v_lot_id is null then raise exception '対象QRロットが見つかりません' using errcode='P0002'; end if;
    v_context:=public.seika_quality_buyer_context_for_lot_v1159(v_lot_id);
    if not exists(select 1 from jsonb_array_elements(v_context->'acknowledger_profile_ids') x where x#>>'{}'=v_profile.id::text) then raise exception 'この品質評価を確認する担当ではありません' using errcode='42501'; end if;
  end if;

  v_already:=v_evaluation.acknowledged_at is not null;
  if not v_already then
    update public.qr_quality_evaluations set acknowledged_at=now(),acknowledged_by=v_profile.id,acknowledged_by_name=coalesce(v_profile.display_name,'（名称未設定）') where id=v_evaluation.id;
  end if;
  return jsonb_build_object('ok',true,'evaluation_id',v_evaluation.id,'already_acknowledged',v_already,
    'acknowledged_at',case when v_already then v_evaluation.acknowledged_at else now() end,
    'acknowledged_by',case when v_already then v_evaluation.acknowledged_by else v_profile.id end,
    'acknowledged_by_name',case when v_already then v_evaluation.acknowledged_by_name else coalesce(v_profile.display_name,'（名称未設定）') end);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_feedback_count_v195()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count bigint;
begin
  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and active
      and role = 'admin'
  ) then
    raise exception '管理者権限が必要です'
      using errcode = '42501';
  end if;

  select count(*)
  into v_count
  from public.seika_feedback_reports
  where status = 'new';

  return jsonb_build_object(
    'ok', true,
    'count', v_count
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_list_feedback_reports_v195()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_reports jsonb;
begin
  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and active
      and role = 'admin'
  ) then
    raise exception '管理者権限が必要です'
      using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(r)
      order by
        case r.status
          when 'new' then 0
          when 'reviewing' then 1
          when 'planned' then 2
          else 3
        end,
        r.created_at desc
    ),
    '[]'::jsonb
  )
  into v_reports
  from (
    select
      id,
      reporter_legacy_user_id,
      reporter_name,
      reporter_role,
      category,
      title,
      body,
      screen_name,
      status,
      admin_memo,
      created_at,
      updated_at,
      reviewed_by_name,
      reviewed_at
    from public.seika_feedback_reports
    order by created_at desc
    limit 300
  ) r;

  return jsonb_build_object(
    'ok', true,
    'reports', v_reports
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_update_feedback_report_v195(p_report_id uuid, p_status text, p_admin_memo text DEFAULT ''::text, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_operation_id uuid DEFAULT gen_random_uuid())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_updated_at timestamptz;
begin
  select *
  into v_profile
  from public.profiles
  where id = auth.uid()
    and active
    and role = 'admin';

  if not found then
    raise exception '管理者権限が必要です'
      using errcode = '42501';
  end if;

  if p_status not in (
    'new',
    'reviewing',
    'planned',
    'done'
  ) then
    raise exception '対応状況を確認してください';
  end if;

  if char_length(coalesce(p_admin_memo, '')) > 500 then
    raise exception '管理者メモは500文字以内です';
  end if;

  update public.seika_feedback_reports
  set
    status = p_status,
    admin_memo = trim(coalesce(p_admin_memo, '')),
    reviewed_by = v_profile.id,
    reviewed_by_name = v_profile.display_name,
    reviewed_at = now(),
    updated_at = now()
  where id = p_report_id
    and (
      p_expected_updated_at is null
      or updated_at = p_expected_updated_at
    )
  returning updated_at into v_updated_at;

  if not found then
    raise exception
      '別の管理者が更新しました。一覧を開き直してください。'
      using errcode = '40001';
  end if;

  return jsonb_build_object(
    'ok', true,
    'updated_at', v_updated_at,
    'operation_id', p_operation_id
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_update_profile_v188(p_target_id uuid, p_display_name text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_active boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_target public.profiles%rowtype;
  v_admin_count integer;
begin
  lock table public.profiles in share row exclusive mode;
  select * into v_target from public.profiles where id = p_target_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'message', '対象ユーザーが見つかりません');
  end if;

  if v_target.role = 'admin' and v_target.active
     and (coalesce(p_role, v_target.role) <> 'admin' or coalesce(p_active, v_target.active) = false) then
    select count(*) into v_admin_count from public.profiles where role = 'admin' and active;
    if v_admin_count <= 1 then
      return jsonb_build_object('ok', false, 'message', '最後の有効な管理者は降格・停止できません');
    end if;
  end if;

  update public.profiles
  set display_name = coalesce(p_display_name, display_name),
      role = coalesce(p_role, role),
      active = coalesce(p_active, active)
  where id = p_target_id;
  return jsonb_build_object('ok', true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.apply_qr_lot_operation_v136(p_operation_id uuid, p_qr_key text, p_movement_type text, p_qty numeric, p_after_quantity numeric, p_weight numeric DEFAULT NULL::numeric, p_after_weight numeric DEFAULT NULL::numeric, p_destination text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_memo text DEFAULT NULL::text, p_user_id text DEFAULT NULL::text, p_user_name text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb, p_expected_quantity numeric DEFAULT NULL::numeric, p_fifo_violation_reason text DEFAULT NULL::text, p_fifo_override_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;l public.qr_lots%rowtype;m public.qr_lot_movements%rowtype;ledger public.seika_fifo_operation_requests_v1136%rowtype;p public.seika_item_aging_policies_v1136%rowtype;assess jsonb;payload jsonb;hash text;mode text;before_qty numeric;before_weight numeric;recommended uuid;rankn integer;eligible boolean;decision text;is_admin boolean;actual_after_weight numeric;old_movement uuid;begin
 v:=public.trimming_require_role(array['admin','worker']);is_admin:=(v.role='admin');
 if p_operation_id is null or nullif(btrim(coalesce(p_qr_key,'')),'')is null or p_movement_type<>'出庫' then raise exception 'operation_id、qr_key、および出庫が必要です';end if;
 if p_qty is null or p_qty<=0 or p_after_quantity is null or p_after_quantity<0 or p_weight is not null and p_weight<0 or p_after_weight is not null and p_after_weight<0 then raise exception '数量または重量が不正です';end if;
 payload:=jsonb_build_object('qr_key',btrim(p_qr_key),'movement_type',p_movement_type,'qty',p_qty,'after_quantity',p_after_quantity,'weight',p_weight,'after_weight',p_after_weight,'destination',p_destination,'reason',p_reason,'memo',p_memo,'expected_quantity',p_expected_quantity,'fifo_violation_reason',p_fifo_violation_reason,'fifo_override_reason',p_fifo_override_reason);
 hash:=md5(payload::text);
 -- 既存移動履歴は、台帳に完了済みの同一payloadがある場合だけ冪等再送として返します。
 select * into ledger from public.seika_fifo_operation_requests_v1136 where operation_id=p_operation_id for update;
 if found then
   if ledger.request_hash<>hash or ledger.request_payload is distinct from payload or ledger.qr_key<>btrim(p_qr_key) then return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じoperation_idに異なるpayloadまたはqr_keyは使用できません');end if;
   if ledger.request_status='completed' then return jsonb_build_object('ok',true,'idempotent',true,'movement_id',ledger.movement_id,'lot_id',ledger.lot_id);end if;
 end if;
 select id into old_movement from public.qr_lot_movements where operation_id=p_operation_id;
 if found then return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','operation_idは既存移動履歴に存在しますが、完了済みの同一v1.136台帳がありません。再利用せず新しいoperation_idで確認してください');end if;
 insert into public.seika_fifo_operation_requests_v1136(operation_id,request_hash,request_payload,qr_key,movement_type,request_status,actor_id)values(p_operation_id,hash,payload,btrim(p_qr_key),'出庫','conflict',v.id)on conflict(operation_id)do nothing;
 select * into ledger from public.seika_fifo_operation_requests_v1136 where operation_id=p_operation_id for update;
 if ledger.request_hash<>hash or ledger.request_payload is distinct from payload or ledger.qr_key<>btrim(p_qr_key) then return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じoperation_idに異なるpayloadまたはqr_keyは使用できません');end if;
 if ledger.request_status='completed' then return jsonb_build_object('ok',true,'idempotent',true,'movement_id',ledger.movement_id,'lot_id',ledger.lot_id);end if;
 -- 新規挿入直後だけstatus=conflictを一時状態として使用し、ここから成功時completedへ確定します。
 select * into l from public.qr_lots where qr_key=btrim(p_qr_key) and active=true for update;if not found then delete from public.seika_fifo_operation_requests_v1136 where operation_id=p_operation_id and request_status='conflict';return jsonb_build_object('ok',false,'not_found',true,'message','対象QRロットが見つかりません');end if;
 before_qty:=l.current_qty;before_weight:=l.current_weight;if p_expected_quantity is not null and before_qty<>p_expected_quantity then delete from public.seika_fifo_operation_requests_v1136 where operation_id=p_operation_id and request_status='conflict';return jsonb_build_object('ok',false,'conflict',true,'current_quantity',before_qty,'message','他端末で残数が更新されています');end if;
 if p_after_quantity>before_qty or p_qty<>before_qty-p_after_quantity then raise exception '出庫数量と処理後残数が一致しません';end if;
 mode:=public.seika_v1136_get_fifo_mode();assess:=public.seika_fifo_assess_lot_v1136(l.qr_key);
 select * into p from public.seika_item_aging_policies_v1136 x where x.id=nullif(assess->>'policy_id','')::uuid;
 recommended:=nullif(assess->>'recommended_lot_id','')::uuid;rankn:=nullif(assess->>'selected_rank','')::integer;eligible:=(assess->'target'->>'exclusion_reason')is null and coalesce((assess->>'policy_applicable')::boolean,false);
 if not coalesce((assess->>'policy_applicable')::boolean,false) or mode='disabled' then decision:='not_applicable';elsif recommended=l.id then decision:='recommended';elsif not eligible then decision:='candidate_unavailable';elsif is_admin and nullif(btrim(coalesce(p_fifo_override_reason,'')),'')is not null then decision:='override';else decision:='violation';end if;
 if mode='warn' and decision in('violation','candidate_unavailable')and nullif(btrim(coalesce(p_fifo_violation_reason,'')),'')is null then raise exception 'warnモードではFIFO推奨外または候補外ロット出庫の理由が必須です';end if;
 if mode='enforce' and decision='candidate_unavailable' then raise exception 'enforceモードでは候補外ロットを出庫できません（除外理由: %）',coalesce(assess->'target'->>'exclusion_reason','not_equivalent');end if;
 if mode='enforce' and decision='violation' then raise exception 'enforceモードでは最古FIFO候補を選ぶか、管理者がoverride理由を入力してください';end if;
 if decision='override' then insert into public.seika_fifo_hold_override_audit_v1136(actor_id,event_kind,lot_id,operation_id,reason,detail)values(v.id,'override',l.id,p_operation_id,btrim(p_fifo_override_reason),jsonb_build_object('recommended_lot_id',recommended,'mode',mode,'target_quality_evaluation_id',assess->'target'->>'quality_evaluation_id','target_quality_grade',assess->'target'->>'quality_grade','target_held',assess->'target'->>'held'));end if;
 insert into public.seika_fifo_decision_audit_v1136(operation_id,actor_id,mode,selected_lot_id,recommended_lot_id,selected_rank,decision,violation_reason,override_reason,candidate_snapshot,decision_detail)values(p_operation_id,v.id,mode,l.id,recommended,rankn,decision,nullif(btrim(coalesce(p_fifo_violation_reason,'')),''),case when decision='override' then btrim(p_fifo_override_reason)end,coalesce(assess->'candidates','[]'::jsonb),jsonb_build_object('policy_id',assess->>'policy_id','selected_eligible',eligible,'selected_exclusion_reason',assess->'target'->>'exclusion_reason','selected_quality_evaluation_id',assess->'target'->>'quality_evaluation_id','selected_quality_grade',assess->'target'->>'quality_grade','selected_hold_active',assess->'target'->>'held','exclusion_summary',coalesce(assess->'exclusion_summary','{}'::jsonb),'eligible_count',assess->>'eligible_count','comparison_attributes',assess->'comparison_attributes','full_rank_evaluated',true));
 update public.qr_lots set current_qty=p_after_quantity,current_weight=coalesce(p_after_weight,current_weight),status=case when p_after_quantity>0 then '在庫あり'else'在庫なし'end,updated_at=now()where id=l.id returning * into l;actual_after_weight:=l.current_weight;
 -- 既存partial unique indexの競合を、v1.136台帳の同一payloadに限って冪等成功として扱います。
 select * into m from public.qr_lot_movements where operation_id=p_operation_id;
 if found then
   if ledger.request_hash=hash and ledger.request_payload=payload and ledger.qr_key=l.qr_key then
     update public.seika_fifo_operation_requests_v1136 set lot_id=m.lot_id,movement_id=m.id,request_status='completed',completed_at=coalesce(completed_at,now()) where operation_id=p_operation_id;
     return jsonb_build_object('ok',true,'idempotent',true,'movement_id',m.id,'lot_id',m.lot_id,'message','既存移動履歴と同一payloadを台帳へ確定しました');
   end if;
   raise exception 'operation_idの既存移動履歴とv1.136 request payloadが一致しません';
 end if;
 insert into public.qr_lot_movements(movement_type,lot_id,lot_no,qr_key,item_id,item_name,origin,supplier,cooperative_name,qty,unit,destination,storage_location,user_id,user_name,memo,container_type,lot_manage_type,weight,before_quantity,after_quantity,before_weight,after_weight,weight_status,reason,operation_id,device_meta,operation_meta)values('出庫',l.id,l.lot_no,l.qr_key,l.item_id,l.item_name,l.origin,l.supplier,l.cooperative_name,p_qty,l.unit,p_destination,l.storage_location,v.id::text,coalesce(v.display_name,''),p_memo,l.container_type,l.lot_manage_type,p_weight,before_qty,p_after_quantity,before_weight,actual_after_weight,l.weight_status,p_reason,p_operation_id,coalesce(p_device_meta,'{}'::jsonb),coalesce(p_operation_meta,'{}'::jsonb))returning * into m;
 update public.seika_fifo_operation_requests_v1136 set lot_id=l.id,movement_id=m.id,request_status='completed',completed_at=now()where operation_id=p_operation_id;
 return jsonb_build_object('ok',true,'idempotent',false,'movement_id',m.id,'lot_id',l.id,'before_quantity',before_qty,'after_quantity',p_after_quantity,'before_weight',before_weight,'after_weight',actual_after_weight,'fifo',jsonb_build_object('mode',mode,'decision',decision,'recommended_lot_id',recommended,'full_rank_evaluated',true));end $function$
;
CREATE OR REPLACE FUNCTION public.apply_qr_lot_operation(p_operation_id uuid, p_qr_key text, p_movement_type text, p_qty numeric, p_after_quantity numeric, p_weight numeric DEFAULT NULL::numeric, p_after_weight numeric DEFAULT NULL::numeric, p_destination text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_memo text DEFAULT NULL::text, p_user_id text DEFAULT NULL::text, p_user_name text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb, p_expected_quantity numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_existing public.qr_lot_movements%rowtype;
  v_movement public.qr_lot_movements%rowtype;
  v_request public.seika_qr_operation_requests_v1156%rowtype;
  v_payload jsonb;
  v_result jsonb;
  v_before_qty numeric;
  v_before_weight numeric;
  v_status text;
  v_inserted integer;
begin
  v_profile := public.trimming_require_role(array['admin','worker']);

  if p_operation_id is null then raise exception 'operation_id は必須です'; end if;
  if nullif(btrim(coalesce(p_qr_key, '')), '') is null then raise exception 'qr_key は必須です'; end if;
  if p_qty is null or p_qty < 0 then raise exception 'qty は0以上で指定してください'; end if;
  if p_after_quantity is null or p_after_quantity < 0 then raise exception '処理後数量は0以上で指定してください'; end if;
  if p_movement_type not in ('出庫','廃棄','出庫・調整減','入庫・調整増','差分なし') then
    raise exception '許可されていない操作区分です';
  end if;
  if p_after_weight is not null and p_after_weight < 0 then raise exception '処理後重量は0以上で指定してください'; end if;

  -- 利用者名・利用者IDはブラウザ値を信用せず、認証プロフィールから生成します。
  v_payload := jsonb_build_object(
    'qr_key', p_qr_key,
    'movement_type', p_movement_type,
    'qty', p_qty,
    'after_quantity', p_after_quantity,
    'weight', p_weight,
    'after_weight', p_after_weight,
    'destination', p_destination,
    'reason', p_reason,
    'memo', p_memo,
    'device_meta', coalesce(p_device_meta, '{}'::jsonb),
    'operation_meta', coalesce(p_operation_meta, '{}'::jsonb),
    'expected_quantity', p_expected_quantity
  );

  insert into public.seika_qr_operation_requests_v1156(
    operation_id, request_payload, actor_profile_id, actor_name, actor_role
  ) values (
    p_operation_id,
    v_payload,
    v_profile.id,
    coalesce(v_profile.display_name, ''),
    v_profile.role
  )
  on conflict (operation_id) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select * into v_request
      from public.seika_qr_operation_requests_v1156
     where operation_id = p_operation_id
     for update;

    if v_request.request_payload is distinct from v_payload then
      return jsonb_build_object(
        'ok', false,
        'idempotency_conflict', true,
        'message', '同じoperation_idに異なる処理内容が指定されました。成功扱いにしていません。管理者が履歴を確認してください。'
      );
    end if;

    if v_request.result_payload is not null then
      return v_request.result_payload || jsonb_build_object('idempotent', true);
    end if;
  end if;

  -- 旧版で台帳作成前に完了した操作IDも、内容一致を確認できる範囲で安全に扱います。
  select * into v_existing
    from public.qr_lot_movements
   where operation_id = p_operation_id;
  if found then
    if v_existing.qr_key is distinct from p_qr_key
       or v_existing.movement_type is distinct from p_movement_type
       or v_existing.qty is distinct from p_qty
       or v_existing.after_quantity is distinct from p_after_quantity then
      return jsonb_build_object(
        'ok', false,
        'idempotency_conflict', true,
        'message', '同じoperation_idの既存履歴と処理内容が一致しません。成功扱いにしていません。'
      );
    end if;
    v_result := jsonb_build_object(
      'ok', true, 'idempotent', true,
      'movement_id', v_existing.id,
      'lot_id', v_existing.lot_id,
      'before_quantity', v_existing.before_quantity,
      'after_quantity', v_existing.after_quantity,
      'before_weight', v_existing.before_weight,
      'after_weight', v_existing.after_weight
    );
    update public.seika_qr_operation_requests_v1156
       set result_payload = v_result,
           completed_at = coalesce(completed_at, now())
     where operation_id = p_operation_id;
    return v_result;
  end if;

  select * into v_lot
    from public.qr_lots
   where qr_key = p_qr_key
     and coalesce(active, true) = true
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', '対象QRロットが見つかりません');
  end if;

  v_before_qty := coalesce(v_lot.current_qty, 0);
  v_before_weight := v_lot.current_weight;

  if p_expected_quantity is not null and v_before_qty <> p_expected_quantity then
    return jsonb_build_object(
      'ok', false, 'conflict', true,
      'current_quantity', v_before_qty,
      'message', '他の端末で残数が更新されています。ロットを開き直して確認してください。'
    );
  end if;

  if p_movement_type in ('出庫','廃棄','出庫・調整減')
     and (p_after_quantity > v_before_qty or p_qty <> v_before_qty - p_after_quantity) then
    raise exception '減少数量と処理後残数が一致しません';
  end if;
  if p_movement_type = '入庫・調整増'
     and (p_after_quantity < v_before_qty or p_qty <> p_after_quantity - v_before_qty) then
    raise exception '増加数量と処理後残数が一致しません';
  end if;
  if p_movement_type = '差分なし'
     and (p_qty <> 0 or p_after_quantity <> v_before_qty) then
    raise exception '差分なしの数量が一致しません';
  end if;

  v_status := case when p_after_quantity > 0 then '在庫あり' else '在庫なし' end;
  update public.qr_lots
     set current_qty = p_after_quantity,
         current_weight = coalesce(p_after_weight, current_weight),
         status = v_status,
         updated_at = now()
   where id = v_lot.id
   returning * into v_lot;

  insert into public.qr_lot_movements(
    movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
    qty, unit, destination, storage_location, user_id, user_name, memo,
    container_type, lot_manage_type, weight, before_quantity, after_quantity,
    before_weight, after_weight, weight_status, reason,
    operation_id, device_meta, operation_meta
  ) values (
    p_movement_type, v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id,
    v_lot.item_name, v_lot.origin, v_lot.supplier, v_lot.cooperative_name, p_qty, v_lot.unit,
    p_destination, v_lot.storage_location, v_profile.id::text, coalesce(v_profile.display_name, ''), p_memo,
    v_lot.container_type, v_lot.lot_manage_type, p_weight, v_before_qty,
    p_after_quantity, v_before_weight, p_after_weight, v_lot.weight_status,
    p_reason, p_operation_id, coalesce(p_device_meta, '{}'::jsonb),
    coalesce(p_operation_meta, '{}'::jsonb)
  ) returning * into v_movement;

  v_result := jsonb_build_object(
    'ok', true, 'idempotent', false,
    'movement_id', v_movement.id,
    'lot_id', v_lot.id,
    'before_quantity', v_before_qty,
    'after_quantity', p_after_quantity,
    'before_weight', v_before_weight,
    'after_weight', p_after_weight
  );

  update public.seika_qr_operation_requests_v1156
     set result_payload = v_result,
         completed_at = now()
   where operation_id = p_operation_id;

  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.approve_fifo_mode_transition_v1136(p_request_id uuid, p_reason text, p_confirm_checks boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype; r public.seika_fifo_mode_transition_approvals_v1136%rowtype; n integer; coverage boolean; b jsonb; a jsonb; begin
 v:=public.trimming_require_role(array['admin']); if p_request_id is null then raise exception '申請IDが必要です'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 or not coalesce(p_confirm_checks,false) then raise exception '承認理由（1〜500文字）と確認チェックが必要です'; end if;
 select * into r from public.seika_fifo_mode_transition_approvals_v1136 where id=p_request_id for update;
 if not found or r.status<>'pending' then raise exception '承認可能な申請がありません'; end if;
 if r.requested_by=v.id then raise exception '申請者本人は承認できません。別の管理者が確認してください'; end if;
 select count(*) into n from public.seika_fifo_decision_audit_v1136 where mode='shadow';
 select not exists(select 1 from public.qr_lots q where q.active and q.status='在庫あり' and q.current_qty>0 and not exists(select 1 from public.seika_item_aging_policies_v1136 p where p.active and p.fifo_enabled and p.effective_from<=current_date and (p.effective_to is null or p.effective_to>=current_date) and ((nullif(btrim(coalesce(q.item_id,'')),'') is not null and nullif(btrim(coalesce(p.item_id,'')),'')=nullif(btrim(coalesce(q.item_id,'')),'') ) or (nullif(btrim(coalesce(q.item_id,'')),'') is null and nullif(btrim(coalesce(p.item_id,'')),'') is null and nullif(btrim(coalesce(p.item_name,'')),'')=nullif(btrim(coalesce(q.item_name,'')),''))))) into coverage;
 if n<r.required_shadow_audit_count or not coverage then raise exception '承認時点のshadow監査数または全対象ポリシー条件を満たしません'; end if;
 select to_jsonb(x) into b from public.seika_feature_modes_v1136 x where feature_key='smart_fifo' for update;
 update public.seika_fifo_mode_transition_approvals_v1136 set status='approved',decided_at=now(),decided_by=v.id,decision_reason=btrim(p_reason),approver_confirmed=true where id=r.id returning * into r;
 update public.seika_feature_modes_v1136 set mode=r.target_mode,updated_at=now(),updated_by=v.id,update_reason='承認申請 '||r.id::text||': '||btrim(p_reason) where feature_key='smart_fifo' returning to_jsonb(seika_feature_modes_v1136.*) into a;
 insert into public.seika_policy_audit_v1136(audited_by,audit_kind,subject_key,action,before_state,after_state,reason) values(v.id,'mode_transition',r.id::text,'approve',b,jsonb_build_object('approval',to_jsonb(r),'feature_mode',a),btrim(p_reason));
 return jsonb_build_object('ok',true,'mode',r.target_mode,'approval_id',r.id); end $function$
;
CREATE OR REPLACE FUNCTION public.assert_app_state_not_rollback_v185(p_old jsonb, p_new jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_key text;
  v_old_count integer;
  v_new_count integer;
  v_severe_count integer := 0;
  v_details text[] := array[]::text[];
begin
  if p_new is null or jsonb_typeof(p_new) <> 'object' then
    raise exception '不正なapp_stateデータです' using errcode = '22023';
  end if;

  foreach v_key in array array[
    'records','specialRecords','movements','wasteRecords',
    'items','qrManagedItems','users','operationLogs'
  ] loop
    if jsonb_typeof(p_old -> v_key) = 'array' then
      v_old_count := jsonb_array_length(p_old -> v_key);
      v_new_count := case when jsonb_typeof(p_new -> v_key) = 'array'
        then jsonb_array_length(p_new -> v_key) else 0 end;
      if v_old_count >= 10
         and (v_new_count > 0 or v_key not in ('records','movements','wasteRecords'))
         and v_new_count <= v_old_count - greatest(10, ceil(v_old_count * 0.20)::integer) then
        v_severe_count := v_severe_count + 1;
        v_details := array_append(v_details, format('%s:%s→%s', v_key, v_old_count, v_new_count));
      end if;
    end if;
  end loop;

  if v_severe_count >= 2
     and coalesce(p_operation_meta ->> 'action', '') not in (
       'history_cleanup_authorized',
       'backup_restore_authorized'
     ) then
    raise exception '巻き戻り防止: 複数データが同時に大幅減少しています（%）',
      array_to_string(v_details, ', ')
      using errcode = 'P0001';
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.backup_app_state_before_update_v185()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if old.data is distinct from new.data then
    insert into public.app_state_backups(
      state_id, state_version, state_updated_at, data,
      last_operation_id, last_device_meta, last_operation_meta
    ) values (
      old.id, old.version, old.updated_at, old.data,
      old.last_operation_id, old.last_device_meta, old.last_operation_meta
    );
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.can_modify_app_state()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select coalesce(public.current_app_role() in ('admin','worker','buyer','sales','clerk'), false)
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_qr_inventory_session(p_session_id uuid, p_cancel_operation_id uuid, p_user_id text DEFAULT NULL::text, p_user_name text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb, p_memo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_session public.qr_inventory_sessions%rowtype;
  v_entry jsonb;
  v_lot public.qr_lots%rowtype;
  v_original public.qr_lot_movements%rowtype;
  v_cancel_entry_operation_id uuid;
  v_result jsonb := '[]'::jsonb;
begin
  if p_session_id is null or p_cancel_operation_id is null then raise exception 'session_id と取消operation_idは必須です'; end if;
  select * into v_session from public.qr_inventory_sessions where session_id = p_session_id for update;
  if not found then return jsonb_build_object('ok', false, 'not_found', true, 'message', '棚卸しセッションが見つかりません'); end if;
  if v_session.status = 'cancelled' then
    if v_session.cancel_operation_id = p_cancel_operation_id then return jsonb_build_object('ok', true, 'idempotent', true, 'session_id', p_session_id, 'status', 'cancelled'); end if;
    return jsonb_build_object('ok', false, 'already_cancelled', true, 'message', 'この棚卸しセッションはすでに取り消されています');
  end if;

  -- 既存の単体取消と同じく、履歴を安定順で先にロックしてからロットを安定順でロックします。
  -- request_entries はconfirm時にtrim済みですが、旧データにも安全なようにここでもbtrimします。
  for v_entry in select value from jsonb_array_elements(v_session.request_entries) order by btrim(value->>'qr_key') loop
    select * into v_original from public.qr_lot_movements
    where operation_id = public.qr_inventory_entry_operation_id(v_session.operation_id, btrim(v_entry->>'qr_key')) for update;
    if not found or v_original.reversed_operation_id is not null then
      return jsonb_build_object('ok', false, 'conflict', true, 'qr_key', btrim(v_entry->>'qr_key'), 'message', '棚卸し履歴が見つからないか、すでに取り消されています');
    end if;
  end loop;
  for v_entry in select value from jsonb_array_elements(v_session.request_entries) order by btrim(value->>'qr_key') loop
    select * into v_lot from public.qr_lots where qr_key = btrim(v_entry->>'qr_key') for update;
    if not found then return jsonb_build_object('ok', false, 'not_found', true, 'qr_key', btrim(v_entry->>'qr_key'), 'message', '対象QRロットが見つかりません'); end if;
    select * into v_original from public.qr_lot_movements
    where operation_id = public.qr_inventory_entry_operation_id(v_session.operation_id, btrim(v_entry->>'qr_key'));
    -- operation_idがNULLの旧履歴も含め、元棚卸し履歴以降にある全履歴を検知します。
    -- 同じロットに同セッションの別明細は作れないため、元履歴自身だけを除外します。
    if coalesce(v_lot.current_qty, 0) <> coalesce(v_original.after_quantity, 0)
       or exists (
         select 1 from public.qr_lot_movements m
         where m.lot_id = v_lot.id
           and (
             m.created_at > v_original.created_at
             or (m.created_at = v_original.created_at and m.id > v_original.id)
           )
       ) then
      return jsonb_build_object('ok', false, 'conflict', true, 'qr_key', btrim(v_entry->>'qr_key'), 'message', '棚卸し後に別処理があります。全件取消はできません');
    end if;
  end loop;

  for v_entry in select value from jsonb_array_elements(v_session.request_entries) order by btrim(value->>'qr_key') loop
    select * into v_lot from public.qr_lots where qr_key = btrim(v_entry->>'qr_key') for update;
    select * into v_original from public.qr_lot_movements where operation_id = public.qr_inventory_entry_operation_id(v_session.operation_id, btrim(v_entry->>'qr_key')) for update;
    v_cancel_entry_operation_id := public.qr_inventory_entry_operation_id(p_cancel_operation_id, btrim(v_entry->>'qr_key'));
    update public.qr_lots set current_qty = v_original.before_quantity, current_weight = v_original.before_weight, status = case when coalesce(v_original.before_quantity, 0) > 0 then '在庫あり' else '在庫なし' end, updated_at = now() where id = v_lot.id;
    insert into public.qr_lot_movements (
      movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name, qty, unit,
      destination, storage_location, user_id, user_name, memo, container_type, lot_manage_type, weight,
      before_quantity, after_quantity, before_weight, after_weight, weight_status, reason,
      operation_id, reversed_operation_id, device_meta, operation_meta
    ) values (
      '棚卸し取消', v_original.lot_id, v_original.lot_no, v_original.qr_key, v_original.item_id,
      v_original.item_name, v_original.origin, v_original.supplier, (select cooperative_name from public.qr_lots where id=v_original.lot_id), coalesce(v_original.qty, 0),
      v_original.unit, v_original.destination, v_original.storage_location, p_user_id, p_user_name,
      coalesce(p_memo, 'QR棚卸しセッションの取消'), v_original.container_type, v_original.lot_manage_type,
      v_original.weight, v_original.after_quantity, v_original.before_quantity,
      v_original.after_weight, v_original.before_weight, v_original.weight_status, 'QR棚卸し取消',
      v_cancel_entry_operation_id, v_original.operation_id, coalesce(p_device_meta, '{}'::jsonb),
      coalesce(p_operation_meta, '{}'::jsonb) || jsonb_build_object('inventory_session_id', p_session_id, 'cancel_operation_id', p_cancel_operation_id)
    );
    update public.qr_lot_movements set reversed_operation_id = v_cancel_entry_operation_id, cancelled_at = now(), cancelled_by = coalesce(p_user_id, p_user_name) where id = v_original.id;
    v_result := v_result || jsonb_build_array(jsonb_build_object('qr_key', v_original.qr_key, 'after_quantity', v_original.before_quantity));
  end loop;
  update public.qr_inventory_sessions set status = 'cancelled', cancelled_at = now(), cancelled_by = coalesce(p_user_id, p_user_name), cancel_operation_id = p_cancel_operation_id, cancel_request_entries = v_session.request_entries where session_id = p_session_id;
  return jsonb_build_object('ok', true, 'idempotent', false, 'session_id', p_session_id, 'status', 'cancelled', 'entries', v_result);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_qr_lot_operation(p_cancel_operation_id uuid, p_original_operation_id uuid, p_user_id text DEFAULT NULL::text, p_user_name text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb, p_memo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_original public.qr_lot_movements%rowtype;
  v_cancel public.qr_lot_movements%rowtype;
  v_lot public.qr_lots%rowtype;
  v_status text;
begin
  if p_cancel_operation_id is null or p_original_operation_id is null then
    raise exception '取消operation_idと元operation_idは必須です';
  end if;
  if p_cancel_operation_id = p_original_operation_id then
    raise exception '取消operation_idは元operation_idと異なる値にしてください';
  end if;

  select * into v_cancel from public.qr_lot_movements where operation_id = p_cancel_operation_id;
  if found then
    return jsonb_build_object('ok', true, 'idempotent', true, 'movement_id', v_cancel.id, 'lot_id', v_cancel.lot_id, 'after_quantity', v_cancel.after_quantity);
  end if;

  select * into v_original
  from public.qr_lot_movements
  where operation_id = p_original_operation_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', '取消対象の操作履歴が見つかりません');
  end if;
  if v_original.reversed_operation_id is not null then
    return jsonb_build_object('ok', false, 'already_cancelled', true, 'message', 'この操作はすでに取り消されています');
  end if;

  select * into v_lot from public.qr_lots where id = v_original.lot_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', '対象QRロットが見つかりません');
  end if;

  -- 数量がたまたま一致していても、元履歴以降の履歴（operation_id が NULL の旧履歴を含む）が
  -- 1件でもあれば取消しません。履歴→ロットの順でロックするため、セッション取消と順序を統一します。
  if coalesce(v_lot.current_qty, 0) <> coalesce(v_original.after_quantity, 0)
     or exists (
       select 1 from public.qr_lot_movements m
       where m.lot_id = v_lot.id
         and (
           m.created_at > v_original.created_at
           or (m.created_at = v_original.created_at and m.id > v_original.id)
         )
     ) then
    return jsonb_build_object('ok', false, 'conflict', true, 'current_quantity', v_lot.current_qty, 'message', '取消対象の後に別処理があります。管理者が履歴を確認してから調整してください。');
  end if;

  v_status := case when coalesce(v_original.before_quantity, 0) > 0 then '在庫あり' else '在庫なし' end;
  update public.qr_lots
  set current_qty = v_original.before_quantity,
      current_weight = v_original.before_weight,
      status = v_status,
      updated_at = now()
  where id = v_lot.id
  returning * into v_lot;

  insert into public.qr_lot_movements (
    movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
    qty, unit, destination, storage_location, user_id, user_name, memo,
    container_type, lot_manage_type, weight, before_quantity, after_quantity,
    before_weight, after_weight, weight_status, reason,
    operation_id, reversed_operation_id, device_meta, operation_meta
  ) values (
    '取消', v_original.lot_id, v_original.lot_no, v_original.qr_key,
    v_original.item_id, v_original.item_name, v_original.origin, v_original.supplier, (select cooperative_name from public.qr_lots where id=v_original.lot_id),
    coalesce(v_original.qty, 0), v_original.unit, v_original.destination,
    v_original.storage_location, p_user_id, p_user_name,
    coalesce(p_memo, '直前QR操作の取消'), v_original.container_type,
    v_original.lot_manage_type, v_original.weight,
    v_original.after_quantity, v_original.before_quantity,
    v_original.after_weight, v_original.before_weight, v_original.weight_status,
    coalesce(v_original.reason, '直前QR操作の取消'),
    p_cancel_operation_id, p_original_operation_id,
    coalesce(p_device_meta, '{}'::jsonb), coalesce(p_operation_meta, '{}'::jsonb)
  ) returning * into v_cancel;

  update public.qr_lot_movements
  set reversed_operation_id = p_cancel_operation_id,
      cancelled_at = now(),
      cancelled_by = coalesce(p_user_id, p_user_name)
  where id = v_original.id;

  return jsonb_build_object('ok', true, 'idempotent', false, 'movement_id', v_cancel.id, 'lot_id', v_lot.id, 'after_quantity', v_lot.current_qty);
exception
  when unique_violation then
    select * into v_cancel from public.qr_lot_movements where operation_id = p_cancel_operation_id;
    if found then
      return jsonb_build_object('ok', true, 'idempotent', true, 'movement_id', v_cancel.id, 'lot_id', v_cancel.lot_id, 'after_quantity', v_cancel.after_quantity);
    end if;
    raise;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_qr_quality_photo_upload_v1102(p_photo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_photo public.qr_quality_photos%rowtype;
begin
  select * into v_profile from public.seika_quality_profile_v1102();if not found or v_profile.role not in ('admin','worker') then raise exception '品質写真の取消権限がありません' using errcode='42501';end if;
  select ph.* into v_photo from public.qr_quality_photos ph join public.qr_quality_evaluations e on e.id=ph.evaluation_id and e.active=true join public.qr_lots q on q.qr_key=e.qr_key and q.active=true where ph.id=p_photo_id and ph.active=true for update of ph;if not found then return jsonb_build_object('ok',true,'already_removed',true);end if;if v_photo.uploaded_by<>v_profile.id or v_photo.upload_status<>'pending' then raise exception 'この品質写真予約は取り消せません' using errcode='42501';end if;if exists(select 1 from storage.objects o where o.bucket_id='qr-quality-photos' and o.name=v_photo.storage_path) then raise exception '先に写真本体をStorage APIで削除してください';end if;delete from public.qr_quality_photos where id=v_photo.id;return jsonb_build_object('ok',true,'photo_id',v_photo.id);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_trimming_job_legacy_v1144(p_job_id uuid, p_operation_id uuid, p_user_name text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles; v_job public.trimming_jobs; l public.trimming_job_lots; o public.trimming_job_outputs; q public.qr_lots; v_state_row public.app_state; v_state jsonb; v_records jsonb; v_moves jsonb; v_current numeric; v_after numeric; v_record_id text; v_move_id text; v_state_version bigint;
begin
  v_profile:=public.trimming_require_role(array['admin','worker','buyer']);
  if p_operation_id is null then raise exception 'operation_id は必須です' using errcode='22023'; end if;
  select * into v_job from public.trimming_jobs where id=p_job_id for update;
  if not found then
    if exists(select 1 from public.qr_lot_movements m where m.operation_id=p_operation_id and m.movement_type='トリミング取消' and m.memo=concat('trimming_job_id=',p_job_id)) then return jsonb_build_object('ok',true,'idempotent',true,'cancelled_job_id',p_job_id); end if;
    raise exception 'トリミング記録が見つかりません（既に取消済みの可能性があります）' using errcode='22023';
  end if;
  if exists(select 1 from public.trimming_job_outputs where trimming_job_id=p_job_id and apply_to_normal_inventory) then
    v_state_row:=public.trimming_lock_inventory_state(); if v_state_row.id <> 'ishioka_inventory_production_v2' and exists(select 1 from public.app_state where id = 'ishioka_inventory_production_v2') then raise exception '現行通常在庫app_stateへ移行後に取消してください' using errcode='22023'; end if; v_state:=v_state_row.data; v_records:=coalesce(v_state->'records','[]'::jsonb); v_moves:=coalesce(v_state->'movements','[]'::jsonb);
    for o in select * from public.trimming_job_outputs where trimming_job_id=p_job_id and apply_to_normal_inventory order by item_id,item_name loop
      select coalesce((r->>'total')::numeric,0) into v_current from jsonb_array_elements(v_records) r where r->>'itemId'=o.item_id order by case when coalesce(r->>'createdAt','') ~ '^\d{4}-\d{2}-\d{2}T' then (r->>'createdAt')::timestamptz end desc nulls last limit 1; v_current:=coalesce(v_current,0);
      if v_current+0.0001<o.output_weight_kg then raise exception '通常在庫が不足しているため取消できません: %（現在 %kg / 必要 %kg）',o.item_name,v_current,o.output_weight_kg using errcode='22023'; end if;
    end loop;
  end if;
  for l in select * from public.trimming_job_lots where trimming_job_id=p_job_id order by qr_key loop
    select * into q from public.qr_lots where id::text=l.qr_lot_id for update; if not found then raise exception 'QRロットが見つからないため取消できません: %',l.qr_key using errcode='22023'; end if;
    update public.qr_lots set current_qty=round(coalesce(q.current_qty,0)+l.used_qty,4),current_weight=case when q.current_weight is null then null else round(q.current_weight+l.used_weight_kg,3) end,updated_at=now() where id=q.id;
    insert into public.qr_lot_movements(movement_type,lot_id,lot_no,qr_key,item_id,item_name,origin,supplier,qty,unit,weight,before_quantity,after_quantity,before_weight,after_weight,reason,memo,user_id,user_name,operation_id,occurred_at)
      values('トリミング取消',q.id,q.lot_no,q.qr_key,q.item_id,q.item_name,q.origin,q.supplier,l.used_qty,q.unit,l.used_weight_kg,coalesce(q.current_qty,0),round(coalesce(q.current_qty,0)+l.used_qty,4),q.current_weight,case when q.current_weight is null then null else round(q.current_weight+l.used_weight_kg,3) end,'トリミング取消',concat('trimming_job_id=',p_job_id),v_profile.id,coalesce(p_user_name,v_profile.display_name,''),p_operation_id,now());
  end loop;
  if v_state_row.id is not null then
    for o in select * from public.trimming_job_outputs where trimming_job_id=p_job_id and apply_to_normal_inventory order by item_id,item_name loop
      select coalesce((r->>'total')::numeric,0) into v_current from jsonb_array_elements(v_records) r where r->>'itemId'=o.item_id order by case when coalesce(r->>'createdAt','') ~ '^\d{4}-\d{2}-\d{2}T' then (r->>'createdAt')::timestamptz end desc nulls last limit 1; v_current:=coalesce(v_current,0); v_after:=round(v_current-o.output_weight_kg,3); v_record_id:=extensions.gen_random_uuid()::text; v_move_id:=extensions.gen_random_uuid()::text;
      v_records:=v_records || jsonb_build_array(jsonb_build_object('id',v_record_id,'kind','トリミング取消','itemId',o.item_id,'itemName',o.item_name,'total',v_after,'lines',jsonb_build_array(jsonb_build_object('pack',1,'cases',o.output_weight_kg,'subtotal',o.output_weight_kg,'trimmingJobId',p_job_id)),'user',coalesce(p_user_name,v_profile.display_name,''),'role',v_profile.role,'createdAt',now()));
      v_moves:=v_moves || jsonb_build_array(jsonb_build_object('id',v_move_id,'recordId',v_record_id,'itemId',o.item_id,'itemName',o.item_name,'type','トリミング取消','beforeTotal',v_current,'afterTotal',v_after,'diffKg',-o.output_weight_kg,'memo',concat('trimming_job_id=',p_job_id),'user',coalesce(p_user_name,v_profile.display_name,''),'role',v_profile.role,'createdAt',now()));
    end loop;
    update public.app_state set data=jsonb_set(jsonb_set(v_state,'{records}',v_records,true),'{movements}',v_moves,true),version=version+1,updated_at=now() where id=v_state_row.id returning version into v_state_version;
  end if;
  delete from public.trimming_jobs where id=p_job_id;
  return jsonb_build_object('ok',true,'cancelled_job_id',p_job_id,'app_state_id',v_state_row.id,'app_state_version',v_state_version);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_trimming_job(p_job_id uuid, p_operation_id uuid, p_user_name text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_job public.trimming_jobs;
  v_audit public.trimming_job_cancel_audit_v1144;
  v_reason text := btrim(coalesce(p_user_name,''));
  v_cancelled_at timestamptz;
  v_result jsonb;
begin
  v_profile:=public.trimming_require_role(array['admin','worker','buyer']);
  if p_job_id is null then raise exception 'トリミング記録IDは必須です' using errcode='22023'; end if;
  if p_operation_id is null then raise exception 'operation_id は必須です' using errcode='22023'; end if;

  -- 同一operation_idは、日報削除後でも最初の確定結果をそのまま返します。
  select * into v_audit from public.trimming_job_cancel_audit_v1144 where operation_id=p_operation_id;
  if found then return v_audit.result; end if;

  -- 同一日報を別operation_idで再取消した場合も成功として返します。
  select * into v_audit from public.trimming_job_cancel_audit_v1144
   where job_id=p_job_id and inventory_link_mode='none' order by cancelled_at desc limit 1;
  if found then
    return v_audit.result || jsonb_build_object('ok',true,'idempotent',true,'already_cancelled',true,'cancelled_job_id',p_job_id);
  end if;

  -- 行ロックにより、同時取消は片方だけがaudit INSERT→job DELETEを実行します。
  select * into v_job from public.trimming_jobs where id=p_job_id for update;

  -- 待機中に他トランザクションが取消済みにした場合を再確認します。
  if not found then
    select * into v_audit from public.trimming_job_cancel_audit_v1144 where operation_id=p_operation_id;
    if found then return v_audit.result; end if;
    select * into v_audit from public.trimming_job_cancel_audit_v1144
     where job_id=p_job_id and inventory_link_mode='none' order by cancelled_at desc limit 1;
    if found then
      return v_audit.result || jsonb_build_object('ok',true,'idempotent',true,'already_cancelled',true,'cancelled_job_id',p_job_id);
    end if;
    -- auditにない欠番はlegacyの既存エラー/冪等判定へ委譲します。
    return public.cancel_trimming_job_legacy_v1144(p_job_id,p_operation_id,p_user_name);
  end if;

  if v_job.inventory_link_mode<>'none' then
    return public.cancel_trimming_job_legacy_v1144(p_job_id,p_operation_id,p_user_name);
  end if;

  if v_reason='' or char_length(v_reason)>500 or v_reason ~ '[[:cntrl:]]' then
    raise exception '日報取消の理由は制御文字を含まない1〜500文字で入力してください' using errcode='22023';
  end if;
  v_cancelled_at:=now();
  v_result:=jsonb_build_object(
    'ok',true,'idempotent',false,'already_cancelled',false,
    'cancelled_job_id',p_job_id,'inventory_link_mode','none',
    'reason',v_reason,'cancelled_at',v_cancelled_at
  );
  begin
    insert into public.trimming_job_cancel_audit_v1144(
      operation_id,job_id,inventory_link_mode,reason,cancelled_by_profile_id,cancelled_at,result
    ) values (p_operation_id,p_job_id,'none',v_reason,v_profile.id,v_cancelled_at,v_result);
  exception when unique_violation then
    select * into v_audit from public.trimming_job_cancel_audit_v1144 where operation_id=p_operation_id;
    if found then return v_audit.result; end if;
    select * into v_audit from public.trimming_job_cancel_audit_v1144
      where job_id=p_job_id and inventory_link_mode='none' order by cancelled_at desc limit 1;
    if found then
      return v_audit.result || jsonb_build_object('ok',true,'idempotent',true,'already_cancelled',true,'cancelled_job_id',p_job_id);
    end if;
    raise;
  end;
  delete from public.trimming_jobs where id=p_job_id;
  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.capture_app_state_backup_v1167()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_day date := (v_now at time zone 'Asia/Tokyo')::date;
  v_state_id text := old.id::text;
  v_version text := old.version::text;
  v_hash text;
  v_existing jsonb;
  v_needed boolean;
begin
  if old.data is not distinct from new.data then return new; end if;
  select exists (
    select 1 from (values
      ('daily'::text,pg_catalog.to_char(v_day,'YYYY-MM-DD')),
      ('weekly'::text,pg_catalog.to_char(v_day,'IYYY-"W"IW')),
      ('monthly'::text,pg_catalog.to_char(v_day,'YYYY-MM'))
    ) wanted(slot_kind,slot_key)
    where not exists (
      select 1 from public.app_state_backup_slots_v1167 x
      where x.state_id=v_state_id and x.slot_kind=wanted.slot_kind and x.slot_key=wanted.slot_key
    )
  ) into v_needed;
  if not v_needed then return new; end if;

  v_hash := encode(extensions.digest(convert_to(old.data::text,'UTF8'),'sha256'),'hex');
  insert into public.app_state_backup_blobs_v1167(content_hash,snapshot_data,data_bytes,first_seen_at,first_state_id,first_state_version)
  values (v_hash,old.data,octet_length(convert_to(old.data::text,'UTF8')),v_now,v_state_id,v_version)
  on conflict (content_hash) do nothing;
  select b.snapshot_data into v_existing from public.app_state_backup_blobs_v1167 b where b.content_hash=v_hash;
  if v_existing is distinct from old.data then
    raise exception 'SHA-256ハッシュ衝突またはバックアップ本文不整合を検出しました。' using errcode='P0001';
  end if;

  insert into public.app_state_backup_slots_v1167(state_id,slot_kind,slot_key,content_hash,state_version,snapshot_updated_at,captured_at,captured_by)
  select v_state_id,wanted.slot_kind,wanted.slot_key,v_hash,v_version,v_now,v_now,auth.uid()
  from (values
    ('daily'::text,pg_catalog.to_char(v_day,'YYYY-MM-DD')),
    ('weekly'::text,pg_catalog.to_char(v_day,'IYYY-"W"IW')),
    ('monthly'::text,pg_catalog.to_char(v_day,'YYYY-MM'))
  ) wanted(slot_kind,slot_key)
  on conflict (state_id,slot_kind,slot_key) do nothing;
  return new;
end
$function$
;
CREATE OR REPLACE FUNCTION public.carry_forward_market_prices_v1126(p_source_week date, p_target_week date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_source_week date;
  v_target_week date;
  v_source_count integer := 0;
  v_inserted_count integer := 0;
begin
  v_profile := public.trimming_require_role(array['admin','worker','buyer','clerk']);
  if p_source_week is null then raise exception '元週は必須です' using errcode='22023'; end if;
  v_source_week := public.trimming_week_start(p_source_week);
  v_target_week := public.trimming_week_start(coalesce(p_target_week,v_source_week+7));
  if v_target_week <= v_source_week or mod((v_target_week-v_source_week),7) <> 0 then
    raise exception '対象週は元週より後の月曜日（7日単位）を指定してください' using errcode='22023';
  end if;
  with source_rows as (
    select distinct on (btrim(pp.item_name)) btrim(pp.item_name) as item_name, pp.price_yen_per_kg
    from public.purchase_prices pp
    where pp.week_start=v_source_week and pp.price_yen_per_kg>=0
      and (pp.price_type='market' or regexp_replace(coalesce(pp.supplier,''),'[[:space:]　]+','','g')='市場')
    order by btrim(pp.item_name), pp.updated_at desc, pp.created_at desc, pp.id desc
  ), inserted as (
    insert into public.purchase_prices(week_start,item_name,origin,supplier,price_yen_per_kg,tax_type,price_type,created_by,updated_by)
    select v_target_week,sr.item_name,'','市場',sr.price_yen_per_kg,'税抜','market',v_profile.id,v_profile.id
    from source_rows sr
    on conflict (week_start,item_name,origin,supplier) do nothing
    returning 1
  )
  select (select count(*)::integer from source_rows),(select count(*)::integer from inserted)
  into v_source_count,v_inserted_count;
  return jsonb_build_object('ok',true,'source_week',v_source_week,'target_week',v_target_week,
    'source_count',v_source_count,'inserted_count',v_inserted_count,'skipped_count',v_source_count-v_inserted_count);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.claim_quality_push_jobs_v1144(p_worker text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_limit integer := greatest(1, least(coalesce(p_limit, 20), 20));
declare v_worker text := left(btrim(coalesce(p_worker, '')), 120);
declare v_job public.quality_push_queue_v1144;
declare v_valid boolean;
declare v_jobs jsonb := '[]'::jsonb;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role only'; end if;
  if v_worker = '' then raise exception 'worker is required'; end if;

  for v_job in
    select q.* from public.quality_push_queue_v1144 q
    where (q.status in ('pending','retry') and q.available_at <= now())
       or (q.status = 'processing' and q.lease_until <= now())
    order by q.available_at, q.created_at
    for update skip locked
    limit v_limit
  loop
    select exists(
      select 1
      from public.qr_quality_evaluations e
      join public.web_push_subscriptions_v1144 s on s.id = v_job.subscription_id
      join public.profiles p on p.id = v_job.recipient_profile_id
      where e.id = v_job.evaluation_id
        and e.grade in ('review','bad') and e.active
        and e.invalidated_at is null and not coalesce(e.invalidated_by_lot_delete, false)
        and not exists (
          select 1 from public.qr_quality_evaluations n
          where n.supersedes_id = e.id and n.active and n.invalidated_at is null
            and not coalesce(n.invalidated_by_lot_delete, false)
        )
        and s.active and s.profile_id = p.id
        and p.active and p.role = 'buyer'
    ) into v_valid;

    if not v_valid then
      update public.quality_push_queue_v1144
      set status = 'cancelled', lease_until = null, locked_at = now(), locked_by = v_worker,
          last_error = 'evaluation, recipient, or subscription is no longer eligible', updated_at = now()
      where id = v_job.id;
      continue;
    end if;

    update public.quality_push_queue_v1144
    set status = 'processing', attempt_count = attempt_count + 1, locked_at = now(), locked_by = v_worker,
        lease_until = now() + interval '5 minutes', updated_at = now()
    where id = v_job.id
    returning * into v_job;

    v_jobs := v_jobs || jsonb_build_array(jsonb_build_object(
      'jobId', v_job.id,
      'evaluationId', v_job.evaluation_id,
      'subscriptionId', v_job.subscription_id,
      'payload', v_job.payload,
      'subscription', (select jsonb_build_object('endpoint', s.endpoint, 'keys', jsonb_build_object('p256dh', s.p256dh, 'auth', s.auth_key)) from public.web_push_subscriptions_v1144 s where s.id = v_job.subscription_id)
    ));
  end loop;
  return jsonb_build_object('ok', true, 'jobs', v_jobs);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cleanup_qr_lots()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_target_count integer := 0;
  v_movement_count integer := 0;
  v_scan_count integer := 0;
  v_deleted_count integer := 0;
begin
  select count(*) into v_target_count
  from public.qr_lots l
  where l.active is false
     or (
       coalesce(l.received_date, l.created_at::date) < current_date - 90
       and coalesce(l.current_qty, 0) <= 0
     );

  delete from public.qr_lot_movements m
  where exists (
    select 1 from public.qr_lots l
    where (
      l.active is false
      or (
        coalesce(l.received_date, l.created_at::date) < current_date - 90
        and coalesce(l.current_qty, 0) <= 0
      )
    )
    and (
      m.lot_id = l.id
      or (m.qr_key is not null and m.qr_key = l.qr_key)
      or (m.lot_no is not null and m.lot_no = l.lot_no)
    )
  );
  get diagnostics v_movement_count = row_count;

  delete from public.qr_scan_logs s
  where exists (
    select 1 from public.qr_lots l
    where (
      l.active is false
      or (
        coalesce(l.received_date, l.created_at::date) < current_date - 90
        and coalesce(l.current_qty, 0) <= 0
      )
    )
    and (
      s.lot_id = l.id
      or (s.qr_key is not null and s.qr_key = l.qr_key)
    )
  );
  get diagnostics v_scan_count = row_count;

  delete from public.qr_lots l
  where l.active is false
     or (
       coalesce(l.received_date, l.created_at::date) < current_date - 90
       and coalesce(l.current_qty, 0) <= 0
     );
  get diagnostics v_deleted_count = row_count;

  return jsonb_build_object(
    'ok', true,
    'target_count', v_target_count,
    'deleted_count', v_deleted_count,
    'movement_count', v_movement_count,
    'scan_count', v_scan_count
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.complete_quality_push_job_v1144(p_job_id uuid, p_worker text, p_result text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.quality_push_queue_v1144;
declare v_result text := lower(btrim(coalesce(p_result, '')));
declare v_error text := nullif(left(btrim(coalesce(p_error, '')), 500), '');
declare v_delay interval;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role only'; end if;
  select * into v_job from public.quality_push_queue_v1144
  where id = p_job_id and status = 'processing' and locked_by = left(btrim(coalesce(p_worker, '')), 120)
  for update;
  if not found then return jsonb_build_object('ok', false, 'message', 'job is not locked by this worker'); end if;

  if v_result = 'sent' then
    update public.quality_push_queue_v1144 set status='sent', sent_at=now(), lease_until=null, last_error=null, updated_at=now() where id=v_job.id;
    update public.web_push_subscriptions_v1144 set failure_count=0, last_success_at=now(), updated_at=now() where id=v_job.subscription_id;
  elsif v_result in ('invalid','cancelled') then
    update public.web_push_subscriptions_v1144 set active=false, last_failure_at=now(), failure_count=failure_count+1, updated_at=now() where id=v_job.subscription_id;
    update public.quality_push_queue_v1144 set status='cancelled', lease_until=null, last_error=coalesce(v_error,'subscription is invalid'), updated_at=now() where id=v_job.id;
  elsif v_result = 'retry' then
    if v_job.attempt_count >= 5 then
      update public.quality_push_queue_v1144 set status='dead', lease_until=null, last_error=coalesce(v_error,'maximum retry count reached'), updated_at=now() where id=v_job.id;
    else
      v_delay := make_interval(mins => least(60, power(2, greatest(v_job.attempt_count - 1, 0))::integer));
      update public.quality_push_queue_v1144 set status='retry', available_at=now()+v_delay, lease_until=null, last_error=coalesce(v_error,'temporary delivery failure'), updated_at=now() where id=v_job.id;
      update public.web_push_subscriptions_v1144 set failure_count=failure_count+1, last_failure_at=now(), updated_at=now() where id=v_job.subscription_id;
    end if;
  else
    raise exception 'invalid completion result';
  end if;
  return jsonb_build_object('ok', true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_monthly_archive_saved_v1101(p_module text, p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date := date_trunc('month',p_target_month)::date;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or v_profile.role <> 'admin' then
    raise exception 'Excelä¿å­æ¸ã¿ã®è¨é²ã¯ç®¡çèã®ã¿å®è¡ã§ãã¾ã' using errcode='42501';
  end if;

  update public.seika_monthly_archives
  set status='excel_saved',excel_saved_at=now(),excel_saved_by=v_profile.id,
      excel_saved_by_name=v_profile.display_name,updated_at=now()
  where module=p_module and target_month=v_month
    and status in ('excel_created','excel_saved') and excel_created_at is not null;
  if not found then raise exception 'åã«Excelãä½æãã¦ãã ãã'; end if;

  return jsonb_build_object('ok',true,'status','excel_saved');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_monthly_quality_archive_saved_v1102(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_month date:=date_trunc('month',p_target_month)::date;v_next date:=(date_trunc('month',p_target_month)+interval '1 month')::date;v_archive public.seika_monthly_archives%rowtype;v_rows bigint;v_photos bigint;v_pending bigint;
begin
  select * into v_profile from public.seika_archive_profile_v1101();if not found or v_profile.role<>'admin' then raise exception 'Excel保存済みの記録は管理者のみ実行できます' using errcode='42501';end if;perform pg_advisory_xact_lock(hashtextextended('quality:'||v_month::text,1102));select * into v_archive from public.seika_monthly_archives where module='quality' and target_month=v_month for update;if not found or v_archive.status not in ('excel_created','excel_saved')or v_archive.excel_created_at is null then raise exception '先に品質評価Excelを作成してください';end if;
  select count(distinct e.id),count(p.id)filter(where p.upload_status='finalized'),count(p.id)filter(where p.upload_status='pending')into v_rows,v_photos,v_pending from public.qr_quality_evaluations e join public.qr_lots q on q.qr_key=e.qr_key and q.active=true left join public.qr_quality_photos p on p.evaluation_id=e.id and p.active=true where e.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo');if v_pending<>0 or v_rows<>v_archive.row_count or v_photos<>v_archive.photo_count then raise exception '品質評価または写真が追加・変更されています。Excelを作り直してください';end if;update public.seika_monthly_archives set status='excel_saved',excel_saved_at=now(),excel_saved_by=v_profile.id,excel_saved_by_name=v_profile.display_name,updated_at=now()where module='quality'and target_month=v_month;return jsonb_build_object('ok',true,'status','excel_saved');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_qr_inventory_session(p_session_id uuid, p_operation_id uuid, p_room text, p_entries jsonb, p_user_id text DEFAULT NULL::text, p_user_name text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_session public.qr_inventory_sessions%rowtype;
  v_lot public.qr_lots%rowtype;
  v_entry jsonb;
  v_qr_key text;
  v_expected numeric;
  v_actual numeric;
  v_out numeric;
  v_before_qty numeric;
  v_before_weight numeric;
  v_after_weight numeric;
  v_diff numeric;
  v_move_type text;
  v_entry_operation_id uuid;
  v_count integer;
  v_normalized_entries jsonb;
  v_result jsonb := '[]'::jsonb;
begin
  if p_session_id is null or p_operation_id is null then
    raise exception 'session_id と operation_id は必須です';
  end if;
  if p_room not in ('room2', 'room3') then
    raise exception 'room は room2 または room3 を指定してください';
  end if;
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'entries は1件以上のJSON配列で指定してください';
  end if;
  -- QRキーの前後空白を除いたJSONをセッションに保存・比較します。確認、再送、取消で同一のキーを使います。
  select jsonb_agg(jsonb_set(e.value, '{qr_key}', to_jsonb(nullif(btrim(e.value->>'qr_key'), '')), true) order by e.ordinality)
    into v_normalized_entries
  from jsonb_array_elements(p_entries) with ordinality as e(value, ordinality);
  if v_normalized_entries is null then
    raise exception 'entries は1件以上のJSON配列で指定してください';
  end if;

  -- セッションIDまたは操作IDの再送を先に判定します。jsonb比較なのでキー順は影響しません。
  select * into v_session from public.qr_inventory_sessions
  where session_id = p_session_id or operation_id = p_operation_id
  for update;
  if found then
    if v_session.session_id = p_session_id
       and v_session.operation_id = p_operation_id
       and v_session.room = p_room
       and v_session.request_entries = v_normalized_entries then
      if v_session.status = 'confirmed' then
        return jsonb_build_object('ok', true, 'idempotent', true, 'session_id', v_session.session_id, 'status', v_session.status);
      end if;
      return jsonb_build_object('ok', false, 'already_cancelled', true, 'message', 'この棚卸しセッションは取り消されています');
    end if;
    return jsonb_build_object('ok', false, 'operation_mismatch', true, 'message', '同じ棚卸しセッションまたはoperation_idに異なる内容を送信することはできません');
  end if;

  -- 入力の形式とQR重複を、更新前に全件検証します。
  select count(*) into v_count from jsonb_array_elements(v_normalized_entries);
  if v_count <> (select count(distinct nullif(btrim(value->>'qr_key'), '')) from jsonb_array_elements(v_normalized_entries)) then
    raise exception '同じqr_keyを棚卸し配列に複数回含めることはできません';
  end if;
  for v_entry in select value from jsonb_array_elements(v_normalized_entries) order by value->>'qr_key' loop
    v_qr_key := nullif(btrim(v_entry->>'qr_key'), '');
    v_expected := nullif(v_entry->>'expected_quantity', '')::numeric;
    if v_qr_key is null or v_expected is null or v_expected < 0 then
      raise exception '各明細に qr_key と0以上の expected_quantity が必要です';
    end if;
    if (v_entry ? 'actual_quantity') and nullif(v_entry->>'actual_quantity', '') is not null then
      v_actual := (v_entry->>'actual_quantity')::numeric;
    else
      v_actual := null;
    end if;
    if (v_entry ? 'out_quantity') and nullif(v_entry->>'out_quantity', '') is not null then
      v_out := (v_entry->>'out_quantity')::numeric;
    else
      v_out := null;
    end if;
    if (v_actual is null and v_out is null) or coalesce(v_actual, 0) < 0 or coalesce(v_out, 0) < 0 then
      raise exception '各明細には0以上の actual_quantity または out_quantity が必要です';
    end if;
    if v_out is not null and v_out > v_expected then
      raise exception '簡単出庫数量はexpected_quantityを超えられません';
    end if;
    if v_actual is null then v_actual := v_expected - v_out; end if;
    if v_out is not null and v_actual <> v_expected - v_out then
      raise exception 'actual_quantity と out_quantity の内容が一致しません';
    end if;
  end loop;

  -- 全端末で同じ順序（qr_key昇順）にロックし、デッドロックを避けます。
  for v_entry in select value from jsonb_array_elements(v_normalized_entries) order by value->>'qr_key' loop
    v_qr_key := nullif(btrim(v_entry->>'qr_key'), '');
    select * into v_lot from public.qr_lots where qr_key = v_qr_key for update;
    if not found then
      return jsonb_build_object('ok', false, 'not_found', true, 'qr_key', v_qr_key, 'message', '対象QRロットが見つかりません');
    end if;
    -- UIのスナップショット条件をDB側でも再検証し、別冷蔵庫・無効ロットの
    -- 棚卸し確定を防ぎます。room2には片岡冷蔵庫を含めます。
    if coalesce(v_lot.active, false) is not true
       or (p_room = 'room2' and coalesce(v_lot.storage_location, '') not in ('第2冷蔵庫', '片岡冷蔵庫'))
       or (p_room = 'room3' and coalesce(v_lot.storage_location, '') <> '第3冷蔵庫') then
      return jsonb_build_object('ok', false, 'out_of_scope', true, 'qr_key', v_qr_key, 'room', p_room, 'message', '対象ロットはこの冷蔵庫の有効なQR在庫ではありません');
    end if;
    v_before_qty := coalesce(v_lot.current_qty, 0);
    v_expected := (v_entry->>'expected_quantity')::numeric;
    if v_before_qty <> v_expected then
      return jsonb_build_object('ok', false, 'conflict', true, 'qr_key', v_qr_key, 'expected_quantity', v_expected, 'current_quantity', v_before_qty, 'message', '他の端末で残数が更新されています。再読取して確認してください。');
    end if;
  end loop;

  -- ここまで全件成功して初めて更新します。途中の例外は関数全体をロールバックします。
  for v_entry in select value from jsonb_array_elements(v_normalized_entries) order by value->>'qr_key' loop
    v_qr_key := nullif(btrim(v_entry->>'qr_key'), '');
    select * into v_lot from public.qr_lots where qr_key = v_qr_key for update;
    v_before_qty := coalesce(v_lot.current_qty, 0);
    v_before_weight := v_lot.current_weight;
    v_expected := (v_entry->>'expected_quantity')::numeric;
    v_out := case when (v_entry ? 'out_quantity') and nullif(v_entry->>'out_quantity', '') is not null then (v_entry->>'out_quantity')::numeric else null end;
    v_actual := case when (v_entry ? 'actual_quantity') and nullif(v_entry->>'actual_quantity', '') is not null then (v_entry->>'actual_quantity')::numeric else null end;
    if v_actual is null then v_actual := v_expected - v_out; end if;
    -- 棚卸し実数は0以上、簡単出庫は上の検証により在庫超過なしです。
    if v_actual < 0 then raise exception '処理後数量は0以上で指定してください'; end if;
    v_diff := v_actual - v_before_qty;
    v_move_type := case when v_diff < 0 then '棚卸し・調整減' when v_diff > 0 then '棚卸し・調整増' else '棚卸し・差分なし' end;

    -- 大型容器のみ、現在重量と現在基数の両方が確定している時に基当たりで比例更新します。
    v_after_weight := v_before_weight;
    if v_lot.container_type in ('網コンテナ', '鉄コンテナ', 'パレテーナ')
       and v_before_weight is not null and v_before_qty > 0 then
      v_after_weight := round((v_before_weight / v_before_qty) * v_actual, 3);
    end if;
    v_entry_operation_id := public.qr_inventory_entry_operation_id(p_operation_id, v_qr_key);

    update public.qr_lots
    set current_qty = v_actual,
        current_weight = v_after_weight,
        status = case when v_actual > 0 then '在庫あり' else '在庫なし' end,
        updated_at = now()
    where id = v_lot.id;

    insert into public.qr_lot_movements (
      movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
      qty, unit, destination, storage_location, user_id, user_name, memo, container_type,
      lot_manage_type, weight, before_quantity, after_quantity, before_weight,
      after_weight, weight_status, reason, operation_id, device_meta, operation_meta
    ) values (
      v_move_type, v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id, v_lot.item_name,
      v_lot.origin, v_lot.supplier, v_lot.cooperative_name, abs(v_diff), v_lot.unit, null, v_lot.storage_location,
      p_user_id, p_user_name, coalesce(v_entry->>'memo', 'QR棚卸し'), v_lot.container_type,
      v_lot.lot_manage_type,
      case when v_before_weight is not null and v_after_weight is not null then abs(v_after_weight - v_before_weight) else null end,
      v_before_qty, v_actual, v_before_weight, v_after_weight, v_lot.weight_status,
      case when v_out is not null then '簡単出庫入力' else '実数棚卸し' end,
      v_entry_operation_id, coalesce(p_device_meta, '{}'::jsonb),
      coalesce(p_operation_meta, '{}'::jsonb) || jsonb_build_object('inventory_session_id', p_session_id, 'inventory_operation_id', p_operation_id)
    );
    v_result := v_result || jsonb_build_array(jsonb_build_object('qr_key', v_qr_key, 'before_quantity', v_before_qty, 'after_quantity', v_actual, 'difference', v_diff));
  end loop;

  insert into public.qr_inventory_sessions (session_id, operation_id, request_entries, room, status, confirmed_at, confirmed_by)
  values (p_session_id, p_operation_id, v_normalized_entries, p_room, 'confirmed', now(), coalesce(p_user_id, p_user_name));
  return jsonb_build_object('ok', true, 'idempotent', false, 'session_id', p_session_id, 'status', 'confirmed', 'entries', v_result);
exception when unique_violation then
  -- 並行再送でも、同じ内容だけを冪等成功にします。
  select * into v_session from public.qr_inventory_sessions where session_id = p_session_id or operation_id = p_operation_id;
  if found and v_session.session_id = p_session_id and v_session.operation_id = p_operation_id and v_session.room = p_room and v_session.request_entries = v_normalized_entries and v_session.status = 'confirmed' then
    return jsonb_build_object('ok', true, 'idempotent', true, 'session_id', v_session.session_id, 'status', v_session.status);
  end if;
  raise;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_admin_notice_v1150(p_id text, p_expected_version bigint, p_notice_id text, p_title text, p_body text, p_starts_at date, p_ends_at date, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor record;
  v_state public.app_state%rowtype;
  v_existing public.seika_admin_notice_operations_v1150%rowtype;
  v_request jsonb;
  v_request_hash text;
  v_notice jsonb;
  v_response jsonb;
  v_version bigint;
  v_now timestamptz := now();
begin
  select * into v_actor from public.seika_admin_notice_require_admin_v1150();

  if p_id is null or btrim(p_id) = '' or p_expected_version is null then
    raise exception '状態IDまたは版番号が不正です' using errcode='22023';
  end if;
  if p_operation_id is null or char_length(btrim(p_operation_id)) not between 1 and 200 then
    raise exception '操作IDが不正です' using errcode='22023';
  end if;

  v_request := jsonb_build_object(
    'action','create','stateId',p_id,'expectedVersion',p_expected_version,
    'noticeId',p_notice_id,'title',p_title,'body',p_body,
    'startsAt',p_starts_at,'endsAt',p_ends_at
  );
  v_request_hash := encode(extensions.digest(convert_to(v_request::text, 'UTF8'), 'sha256'), 'hex');

  -- 同じ操作IDの並行実行も直列化します。
  perform pg_advisory_xact_lock(hashtext(p_operation_id));
  select * into v_existing from public.seika_admin_notice_operations_v1150 where operation_id = p_operation_id;
  if found then
    if v_existing.actor_id <> v_actor.actor_id or v_existing.request_hash <> v_request_hash then
      raise exception '同じ操作IDに異なる要求は使用できません' using errcode='22023';
    end if;
    return v_existing.response;
  end if;

  if p_notice_id is null or char_length(btrim(p_notice_id)) not between 1 and 200 then
    raise exception 'お知らせIDが不正です' using errcode='22023';
  end if;
  if p_title is null or char_length(btrim(p_title)) not between 1 and 100 then
    raise exception '件名は1〜100文字で入力してください' using errcode='22023';
  end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 1000 then
    raise exception '内容は1〜1000文字で入力してください' using errcode='22023';
  end if;
  if p_starts_at is not null and p_ends_at is not null and p_starts_at > p_ends_at then
    raise exception '表示開始日と表示終了日を確認してください' using errcode='22023';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then raise exception 'アプリ状態が見つかりません' using errcode='P0002'; end if;
  if v_state.version is distinct from p_expected_version then
    v_response := jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'message','他の端末で更新されています。最新データを取得して再試行してください');
    return v_response;
  end if;

  insert into public.seika_admin_notices_v1150(
    state_id,notice_id,title,body,starts_at,ends_at,active,created_at,created_by,created_by_id,updated_at
  ) values (
    p_id,btrim(p_notice_id),btrim(p_title),btrim(p_body),p_starts_at,p_ends_at,true,v_now,v_actor.actor_name,v_actor.actor_id::text,v_now
  );

  v_version := public.seika_admin_notice_sync_app_state_v1150(p_id);
  select jsonb_build_object('id',notice_id,'title',title,'body',body,'startsAt',starts_at,'endsAt',ends_at,'active',active,'createdAt',created_at,'createdBy',created_by,'createdById',created_by_id,'updatedAt',updated_at)
  into v_notice from public.seika_admin_notices_v1150 where state_id=p_id and notice_id=btrim(p_notice_id);
  v_response := jsonb_build_object('ok',true,'conflict',false,'version',v_version,'operationId',p_operation_id,'notice',v_notice);

  insert into public.seika_admin_notice_audit_v1150(
    state_id,notice_id,action,operation_id,actor_id,actor_role,request_hash,before_notice,after_notice,expected_version,resulting_version
  ) values (
    p_id,btrim(p_notice_id),'create',p_operation_id,v_actor.actor_id,v_actor.actor_role,v_request_hash,null,v_notice,p_expected_version,v_version
  );
  insert into public.seika_admin_notice_operations_v1150(operation_id,actor_id,action,request_hash,response)
  values(p_operation_id,v_actor.actor_id,'create',v_request_hash,v_response);
  return v_response;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_manual_app_state_backup_v1167(p_state_id text, p_operation_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.app_state_backup_slots_v1167%rowtype;
  v_data jsonb;
  v_version text;
  v_hash text;
  v_existing_blob jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_manual_count bigint;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.active is true
  ) then
    raise exception '有効な管理者だけが手動バックアップを作成できます。' using errcode='42501';
  end if;
  if p_state_id is null or pg_catalog.btrim(p_state_id)='' then raise exception 'state_id を指定してください。' using errcode='22023'; end if;
  if p_operation_id is null then raise exception 'operation_id を指定してください。' using errcode='22023'; end if;
  if p_note is not null and pg_catalog.length(p_note)>500 then raise exception 'メモは500文字以内です。' using errcode='22023'; end if;

  -- 同一operation_idの再送と5件上限を、全手動バックアップ共通のトランザクションロックで直列化します。
  perform pg_catalog.pg_advisory_xact_lock(1167,pg_catalog.hashtext('seika:manual_app_state_backup:v1167'));
  select x.* into v_existing from public.app_state_backup_slots_v1167 x
  where x.slot_kind='manual' and x.operation_id=p_operation_id;
  if found then
    if v_existing.state_id is distinct from p_state_id or v_existing.note is distinct from p_note then
      raise exception 'operation_id が別の手動バックアップに使用されています。' using errcode='22023';
    end if;
    return pg_catalog.jsonb_build_object('ok',true,'idempotent',true,'state_id',v_existing.state_id,'slot_kind',v_existing.slot_kind,'slot_key',v_existing.slot_key,'content_hash',v_existing.content_hash,'manual_count_after',(select count(*) from public.app_state_backup_slots_v1167 where slot_kind='manual'));
  end if;

  select count(*) into v_manual_count from public.app_state_backup_slots_v1167 where slot_kind='manual';
  if v_manual_count>=5 then
    raise exception '手動バックアップは5件に達しています。第1段階では自動削除しません。' using errcode='P0001';
  end if;
  select s.data,s.version::text into v_data,v_version from public.app_state s where s.id::text=p_state_id;
  if not found then raise exception '指定したstate_idのapp_stateが見つかりません。' using errcode='22023'; end if;

  v_hash := encode(extensions.digest(convert_to(v_data::text,'UTF8'),'sha256'),'hex');
  insert into public.app_state_backup_blobs_v1167(content_hash,snapshot_data,data_bytes,first_seen_at,first_state_id,first_state_version)
  values(v_hash,v_data,octet_length(convert_to(v_data::text,'UTF8')),v_now,p_state_id,v_version)
  on conflict(content_hash) do nothing;
  select b.snapshot_data into v_existing_blob from public.app_state_backup_blobs_v1167 b where b.content_hash=v_hash;
  if v_existing_blob is distinct from v_data then
    raise exception 'SHA-256ハッシュ衝突またはバックアップ本文不整合を検出しました。' using errcode='P0001';
  end if;

  insert into public.app_state_backup_slots_v1167(state_id,slot_kind,slot_key,content_hash,state_version,snapshot_updated_at,captured_at,captured_by,operation_id,note)
  values(p_state_id,'manual',p_operation_id::text,v_hash,v_version,v_now,v_now,auth.uid(),p_operation_id,p_note);
  return pg_catalog.jsonb_build_object('ok',true,'idempotent',false,'state_id',p_state_id,'slot_kind','manual','slot_key',p_operation_id::text,'content_hash',v_hash,'manual_count_after',v_manual_count+1);
end
$function$
;
CREATE OR REPLACE FUNCTION public.create_qr_lot_v185(p_lot jsonb, p_operation_id uuid, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lot public.qr_lots%rowtype;
  v_move public.qr_lot_movements%rowtype;
  v_qty numeric;
  v_user_id text;
  v_user_name text;
begin
  if p_operation_id is null then
    raise exception 'operation_id は必須です' using errcode = '22023';
  end if;

  select * into v_move
  from public.qr_lot_movements
  where operation_id = p_operation_id;

  if found then
    select * into v_lot from public.qr_lots where id = v_move.lot_id;
    if v_move.movement_type <> '入庫'
       or v_lot.qr_key is distinct from p_lot ->> 'qr_key' then
      raise exception '操作IDが別の処理で使用されています' using errcode = '23505';
    end if;
    return jsonb_build_object('ok', true, 'idempotent', true, 'lot', to_jsonb(v_lot));
  end if;

  v_qty := nullif(p_lot ->> 'received_qty', '')::numeric;
  if nullif(btrim(p_lot ->> 'qr_key'), '') is null
     or nullif(btrim(p_lot ->> 'item_name'), '') is null
     or v_qty is null or v_qty <= 0 then
    raise exception 'QRキー、品名、入庫数量は必須です' using errcode = '22023';
  end if;

  v_user_id := nullif(p_lot ->> 'user_id', '');
  v_user_name := nullif(p_lot ->> 'user_name', '');
  if v_user_id is null or v_user_name is null then
    raise exception '利用者情報を確認できません' using errcode = '22023';
  end if;

  insert into public.qr_lots (
    lot_no, qr_key, item_id, item_name, origin, supplier,
    received_date, received_qty, current_qty, unit, storage_location,
    status, user_id, user_name, memo, active, container_type,
    lot_manage_type, quantity_label, pack_weight, total_weight,
    current_weight, weight_status, purchase_staff, cooperative_name
  ) values (
    p_lot ->> 'lot_no', p_lot ->> 'qr_key', nullif(p_lot ->> 'item_id', ''),
    p_lot ->> 'item_name', nullif(p_lot ->> 'origin', ''),
    nullif(p_lot ->> 'supplier', ''), nullif(p_lot ->> 'received_date', '')::date,
    v_qty, v_qty, p_lot ->> 'unit', nullif(p_lot ->> 'storage_location', ''),
    '在庫あり', v_user_id, v_user_name, nullif(p_lot ->> 'memo', ''), true,
    p_lot ->> 'container_type', p_lot ->> 'lot_manage_type',
    p_lot ->> 'quantity_label', nullif(p_lot ->> 'pack_weight', ''),
    nullif(p_lot ->> 'total_weight', '')::numeric,
    nullif(p_lot ->> 'current_weight', '')::numeric,
    p_lot ->> 'weight_status', nullif(p_lot ->> 'purchase_staff', ''),
    nullif(p_lot ->> 'cooperative_name', '')
  ) returning * into v_lot;

  insert into public.qr_lot_movements (
    occurred_at, movement_type, lot_id, lot_no, qr_key, item_id, item_name,
    origin, supplier, cooperative_name, qty, unit, storage_location,
    user_id, user_name, memo, container_type, lot_manage_type, weight,
    before_quantity, after_quantity, before_weight, after_weight,
    weight_status, reason, operation_id, device_meta, operation_meta
  ) values (
    now(), '入庫', v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id,
    v_lot.item_name, v_lot.origin, v_lot.supplier, v_lot.cooperative_name,
    v_qty, v_lot.unit, v_lot.storage_location, v_user_id, v_user_name,
    case when nullif(v_lot.purchase_staff, '') is not null
      then '仕入れ担当者：' || v_lot.purchase_staff else 'QR入庫' end,
    v_lot.container_type, v_lot.lot_manage_type, v_lot.current_weight,
    0, v_lot.current_qty, 0, v_lot.current_weight, v_lot.weight_status,
    'QR入庫', p_operation_id, coalesce(p_device_meta, '{}'::jsonb),
    coalesce(p_operation_meta, '{}'::jsonb)
  );

  return jsonb_build_object('ok', true, 'idempotent', false, 'lot', to_jsonb(v_lot));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_qr_quality_evaluation_v1102(p_qr_key text, p_grade text, p_issues text[] DEFAULT '{}'::text[], p_memo text DEFAULT NULL::text, p_correction_reason text DEFAULT NULL::text, p_supersedes_id uuid DEFAULT NULL::uuid, p_evaluated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_qr_key text:=btrim(coalesce(p_qr_key,''));v_grade text:=lower(btrim(coalesce(p_grade,'')));v_issues text[]:=array(select distinct btrim(x) from unnest(coalesce(p_issues,'{}'::text[])) x where btrim(x)<>'' order by btrim(x));v_memo text:=nullif(btrim(coalesce(p_memo,'')), '');v_reason text:=nullif(btrim(coalesce(p_correction_reason,'')), '');v_lot record;v_prior public.qr_quality_evaluations%rowtype;v_id uuid;v_at timestamptz:=coalesce(p_evaluated_at,now());
begin
  select * into v_profile from public.seika_quality_profile_v1102();if not found or v_profile.role not in ('admin','worker') then raise exception '品質評価の登録は管理者・青果社員のみです' using errcode='42501';end if;
  if v_qr_key='' or char_length(v_qr_key)>160 then raise exception 'QRキーが不正です';end if;if v_grade not in ('good','review','bad') then raise exception '総合判定は good / review / bad のいずれかです';end if;if cardinality(v_issues)>12 then raise exception '状態は12件までです';end if;if char_length(coalesce(v_memo,''))>1000 then raise exception 'メモは1000文字以内です';end if;if v_grade='good' and cardinality(v_issues)>0 then raise exception '良好の場合は問題項目を登録できません';end if;if v_grade in ('review','bad') and cardinality(v_issues)=0 then raise exception '要確認・不良の場合は状態を1つ以上選択してください';end if;if 'その他'=any(v_issues) and v_memo is null then raise exception 'その他を選んだ場合はメモへ内容を入力してください';end if;if p_supersedes_id is null and v_reason is not null then raise exception '初回評価に訂正理由は登録できません';end if;if p_supersedes_id is not null and v_reason is null then raise exception '訂正理由を入力してください';end if;if char_length(coalesce(v_reason,''))>500 then raise exception '訂正理由は500文字以内です';end if;if v_at>now()+interval '10 minutes' or v_at<now()-interval '366 days' then raise exception '評価日時の範囲が不正です';end if;
  select q.id::text,q.lot_no,q.item_name into v_lot from public.qr_lots q where q.qr_key=v_qr_key and q.active=true order by q.created_at desc limit 1;if not found then raise exception '有効なQRロットが見つかりません';end if;
  perform pg_advisory_xact_lock(hashtextextended('qr-quality:'||v_qr_key,1114));if p_supersedes_id is null and exists(select 1 from public.qr_quality_evaluations e where e.qr_key=v_qr_key and e.supersedes_id is null and e.active=true) then raise exception 'このQRロットは品質評価を登録済みです。訂正を使用してください';end if;
  if p_supersedes_id is not null then select * into v_prior from public.qr_quality_evaluations where id=p_supersedes_id and active=true;if not found or v_prior.qr_key<>v_qr_key then raise exception '訂正対象の品質評価が見つからないか、別ロットです';end if;if exists(select 1 from public.qr_quality_evaluations e where e.supersedes_id=p_supersedes_id and e.active=true) then raise exception 'この品質評価はすでに訂正済みです。最新の評価を訂正してください';end if;if v_at<=v_prior.evaluated_at then raise exception '訂正日時は訂正元の評価日時より後にしてください';end if;end if;
  insert into public.qr_quality_evaluations(qr_key,lot_id,lot_no,item_name,grade,issues,memo,correction_reason,evaluated_at,evaluated_by,evaluated_by_name,supersedes_id) values(v_qr_key,v_lot.id,v_lot.lot_no,v_lot.item_name,v_grade,v_issues,v_memo,v_reason,v_at,v_profile.id,coalesce(v_profile.display_name,'（名称未設定）'),p_supersedes_id) returning id into v_id;return jsonb_build_object('ok',true,'evaluation_id',v_id,'qr_key',v_qr_key);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_qr_quality_photo_upload_v1102(p_evaluation_id uuid, p_original_name text, p_content_type text, p_byte_size bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_eval public.qr_quality_evaluations%rowtype;
  v_type text := lower(btrim(coalesce(p_content_type,'')));
  v_ext text;
  v_path text;
  v_photo_id uuid;
  v_count integer;
  v_name text := left(regexp_replace(coalesce(p_original_name,''),'[^[:alnum:]_. -]','_','g'),160);
begin
  select * into v_profile from public.seika_quality_profile_v1102();
  if not found or v_profile.role not in ('admin','worker') then
    raise exception '品質写真の登録は管理者・青果社員のみです' using errcode = '42501';
  end if;
  if p_evaluation_id is null then
    raise exception '評価IDがありません';
  end if;
  select * into v_eval from public.qr_quality_evaluations where id=p_evaluation_id;
  if not found then
    raise exception '品質評価が見つかりません';
  end if;
  if v_eval.evaluated_by<>v_profile.id then
    raise exception '写真は評価を登録した本人だけが追加できます' using errcode = '42501';
  end if;
  if v_eval.grade='good' then
    raise exception '良好評価には写真を登録できません';
  end if;
  if v_type not in ('image/jpeg','image/png','image/webp') then
    raise exception '写真形式は JPEG / PNG / WebP のみです';
  end if;
  if p_byte_size is null or p_byte_size<=0 or p_byte_size>358400 then
    raise exception '写真は1枚350KB以下に圧縮してください';
  end if;

  -- pendingも数えるため、並行操作でも4枚目の予約はできません。
  perform pg_advisory_xact_lock(hashtextextended(p_evaluation_id::text, 1102));
  select count(*) into v_count from public.qr_quality_photos where evaluation_id=p_evaluation_id;
  if v_count>=3 then
    raise exception '写真は1評価につき最大3枚です';
  end if;

  v_ext := case v_type when 'image/jpeg' then 'jpg' when 'image/png' then 'png' else 'webp' end;
  v_photo_id := gen_random_uuid();
  v_path := 'evaluations/' || p_evaluation_id::text || '/' || v_photo_id::text || '.' || v_ext;
  insert into public.qr_quality_photos(
    id,evaluation_id,storage_path,original_name,content_type,declared_byte_size,uploaded_by
  ) values (
    v_photo_id,p_evaluation_id,v_path,coalesce(nullif(v_name,''),'quality.'||v_ext),v_type,p_byte_size,v_profile.id
  );

  return jsonb_build_object(
    'ok',true,'photo_id',v_photo_id,'bucket','qr-quality-photos',
    'storage_path',v_path,'content_type',v_type,'max_byte_size',358400
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_trimming_job(p_operation_id uuid, p_work_date date, p_lots jsonb, p_outputs jsonb, p_note text DEFAULT ''::text, p_user_name text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles; v_job public.trimming_jobs; v_existing public.trimming_jobs;
  v_lot_input jsonb; v_output_input jsonb; v_lot public.qr_lots;
  v_state public.app_state; v_items jsonb; v_master jsonb;
  v_job_id uuid := extensions.gen_random_uuid(); v_first_item_key text := null;
  v_source_id text := null; v_source_name text := null; v_mode text;
  v_qty numeric; v_weight numeric; v_per numeric; v_input_weight numeric := 0;
  v_output_weight numeric := 0; v_output_weight_one numeric; v_output_qty numeric;
  v_unit_weight numeric; v_item_id text; v_item_name text; v_loss numeric;
begin
  v_profile := public.trimming_require_role(array['admin','worker']);
  if p_operation_id is null or p_work_date is null
     or jsonb_typeof(p_lots) <> 'array' or jsonb_array_length(p_lots)=0
     or jsonb_typeof(p_outputs) <> 'array' or jsonb_array_length(p_outputs)=0 then
    raise exception 'operation_id、作業日、1件以上の使用ロット・入替品が必要です' using errcode='22023';
  end if;
  select * into v_existing from public.trimming_jobs where operation_id=p_operation_id;
  if found then return jsonb_build_object('ok',true,'idempotent',true,'job',to_jsonb(v_existing)); end if;

  -- 品目名の監査用解決だけにapp_stateを参照します。ロック・更新はしません。
  select * into v_state from public.app_state where id='ishioka_inventory_production_v2';
  if not found then select * into v_state from public.app_state where id='ishioka_inventory_demo_v6_linecopy_weekly'; end if;
  if not found or jsonb_typeof(v_state.data->'items') <> 'array' then
    raise exception '通常在庫品目マスタが見つかりません' using errcode='22023';
  end if;
  v_items := coalesce(v_state.data->'items','[]'::jsonb) || coalesce(v_state.data->'specialItems'->'exchange','[]'::jsonb);

  insert into public.trimming_jobs(
    id,operation_id,work_date,week_start,source_item_id,source_item_name,
    input_weight_kg,output_weight_kg,loss_weight_kg,yield_percent,note,
    created_by,created_by_name,inventory_link_mode
  ) values (
    v_job_id,p_operation_id,p_work_date,public.trimming_week_start(p_work_date),'','（処理中）',
    1,0,1,0,coalesce(p_note,''),v_profile.id,coalesce(p_user_name,v_profile.display_name,''),'none'
  );

  for v_lot_input in select value from jsonb_array_elements(p_lots) order by value->>'qr_key' loop
    if btrim(coalesce(v_lot_input->>'qr_key',''))='' then
      raise exception 'qr_key は必須です' using errcode='22023';
    end if;
    -- active/存在だけ参照。残数量・残重量を超えていても拒否せず、いかなる在庫更新もしません。
    select * into v_lot from public.qr_lots where qr_key=v_lot_input->>'qr_key' and active=true;
    if not found then raise exception '有効なQRロットが見つかりません: %',v_lot_input->>'qr_key' using errcode='22023'; end if;
    if v_first_item_key is null then
      v_first_item_key:=coalesce(v_lot.item_id::text,v_lot.item_name);
      v_source_id:=v_lot.item_id::text; v_source_name:=v_lot.item_name;
    elsif v_first_item_key <> coalesce(v_lot.item_id::text,v_lot.item_name) then
      raise exception '同一品目のQRロットだけを登録できます' using errcode='22023';
    end if;
    if exists(select 1 from public.trimming_job_lots x where x.trimming_job_id=v_job_id and x.qr_key=v_lot.qr_key) then
      raise exception '同じQRロットを重複指定できません' using errcode='22023';
    end if;

    v_mode:=v_lot_input->>'usage_mode';
    v_per:=case
      when coalesce(v_lot.current_weight,0)>0 and coalesce(v_lot.current_qty,0)>0 then v_lot.current_weight/v_lot.current_qty
      when coalesce(v_lot.total_weight,0)>0 and coalesce(v_lot.received_qty,0)>0 then v_lot.total_weight/v_lot.received_qty
      when public.seika_parse_kg_v1162(v_lot.pack_weight::text) > 0 then public.seika_parse_kg_v1162(v_lot.pack_weight::text)
      else null end;
    if v_mode='qty' then
      v_qty:=(v_lot_input->>'used_qty')::numeric;
      if v_qty is null or v_qty<=0 or v_per is null or v_per<=0 then
        raise exception '使用数量または重量換算が不正です: %',v_lot.qr_key using errcode='22023';
      end if;
      v_weight:=round(v_qty*v_per,3);
    elsif v_mode='weight' then
      v_weight:=(v_lot_input->>'used_weight_kg')::numeric;
      if v_weight is null or v_weight<=0 then raise exception '使用重量を確認してください: %',v_lot.qr_key using errcode='22023'; end if;
      -- 日報の重量入力は在庫残量によらず保存可能。明細の必須used_qtyには換算値を監査保存します。
      v_qty:=case when v_per is not null and v_per>0 then round(v_weight/v_per,4) else v_weight end;
    else
      raise exception 'usage_mode は qty または weight です' using errcode='22023';
    end if;
    v_input_weight:=v_input_weight+v_weight;
    insert into public.trimming_job_lots(
      trimming_job_id,qr_lot_id,qr_key,lot_no,item_id,item_name,origin,supplier,usage_mode,
      used_qty,used_weight_kg,unit_weight_kg,before_qty,after_qty,before_weight_kg,after_weight_kg,
      purchase_price_yen_per_kg,purchase_price_week_start
    ) values (
      v_job_id,v_lot.id::text,v_lot.qr_key,v_lot.lot_no,v_lot.item_id::text,v_lot.item_name,
      coalesce(v_lot.origin,''),coalesce(v_lot.supplier,''),v_mode,v_qty,v_weight,v_per,
      coalesce(v_lot.current_qty,0),coalesce(v_lot.current_qty,0),v_lot.current_weight,v_lot.current_weight,
      null,null
    );
  end loop;

  for v_output_input in select value from jsonb_array_elements(p_outputs) loop
    v_item_id:=nullif(btrim(coalesce(v_output_input->>'item_id','')),'');
    v_item_name:=nullif(btrim(coalesce(v_output_input->>'item_name','')),'');
    v_mode:=v_output_input->>'mode';
    v_master:=null;
    if v_mode not in ('weight','qty') or (v_item_id is null and v_item_name is null) then
      raise exception '入替品名とmodeが必要です' using errcode='22023';
    end if;
    if v_item_id is not null then
      select i into v_master from jsonb_array_elements(v_items) i
        where i->>'id'=v_item_id and coalesce((i->>'active')::boolean,true) limit 1;
      if v_master is null then raise exception '有効な入替品候補が見つかりません: %',v_item_id using errcode='22023'; end if;
      v_item_name:=btrim(v_master->>'name');
    elsif char_length(v_item_name)>100 then
      raise exception '手入力の入替品名は100文字以内です' using errcode='22023';
    end if;
    if v_mode='weight' then
      v_output_weight_one:=(v_output_input->>'output_weight_kg')::numeric; v_output_qty:=null; v_unit_weight:=null;
    else
      v_output_qty:=(v_output_input->>'output_qty')::numeric; v_unit_weight:=(v_output_input->>'unit_weight_kg')::numeric;
      v_output_weight_one:=round(v_output_qty*v_unit_weight,3);
    end if;
    if v_output_weight_one is null or v_output_weight_one<=0
       or (v_mode='qty' and (v_output_qty<=0 or v_unit_weight<=0)) then
      raise exception '入替品の重量・数量が不正です' using errcode='22023';
    end if;
    v_output_weight:=v_output_weight+v_output_weight_one;
    -- payloadのtrueも必ずfalseとして保存。通常在庫IDと前後数量は常にNULLです。
    insert into public.trimming_job_outputs(
      trimming_job_id,item_id,item_name,output_weight_kg,output_qty,unit_weight_kg,mode,
      apply_to_normal_inventory,normal_inventory_record_id,normal_inventory_movement_id,
      normal_before_total_kg,normal_after_total_kg
    ) values (v_job_id,v_item_id,v_item_name,v_output_weight_one,v_output_qty,v_unit_weight,v_mode,false,null,null,null,null);
  end loop;
  
  v_loss:=round(v_input_weight-v_output_weight,3);
  update public.trimming_jobs set source_item_id=v_source_id,source_item_name=v_source_name,
    input_weight_kg=round(v_input_weight,3),output_weight_kg=round(v_output_weight,3),
    loss_weight_kg=v_loss,yield_percent=round(v_output_weight/nullif(v_input_weight,0)*100,3),
    purchase_price_yen_per_kg=null,input_cost_yen=null,updated_at=now(),inventory_link_mode='none'
  where id=v_job_id returning * into v_job;
  perform public.recalc_trimming_job_price_v1195(v_job_id);
  select * into v_job from public.trimming_jobs where id=v_job_id;
  return jsonb_build_object('ok',true,'idempotent',false,'job',to_jsonb(v_job));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.current_app_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.active = true
  limit 1
$function$
;
CREATE OR REPLACE FUNCTION public.delete_admin_notice_v1150(p_id text, p_expected_version bigint, p_notice_id text, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor record;
  v_state public.app_state%rowtype;
  v_existing public.seika_admin_notice_operations_v1150%rowtype;
  v_before jsonb;
  v_request jsonb;
  v_request_hash text;
  v_response jsonb;
  v_version bigint;
begin
  select * into v_actor from public.seika_admin_notice_require_admin_v1150();
  if p_id is null or btrim(p_id) = '' or p_expected_version is null then raise exception '状態IDまたは版番号が不正です' using errcode='22023'; end if;
  if p_notice_id is null or char_length(btrim(p_notice_id)) not between 1 and 200 then raise exception 'お知らせIDが不正です' using errcode='22023'; end if;
  if p_operation_id is null or char_length(btrim(p_operation_id)) not between 1 and 200 then raise exception '操作IDが不正です' using errcode='22023'; end if;

  v_request:=jsonb_build_object('action','delete','stateId',p_id,'expectedVersion',p_expected_version,'noticeId',p_notice_id);
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtext(p_operation_id));
  select * into v_existing from public.seika_admin_notice_operations_v1150 where operation_id=p_operation_id;
  if found then
    if v_existing.actor_id <> v_actor.actor_id or v_existing.request_hash <> v_request_hash then raise exception '同じ操作IDに異なる要求は使用できません' using errcode='22023'; end if;
    return v_existing.response;
  end if;

  select * into v_state from public.app_state where id=p_id for update;
  if not found then raise exception 'アプリ状態が見つかりません' using errcode='P0002'; end if;
  if v_state.version is distinct from p_expected_version then
    v_response:=jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'message','他の端末で更新されています。最新データを取得して再試行してください');
    return v_response;
  end if;

  delete from public.seika_admin_notices_v1150
  where state_id=p_id and notice_id=btrim(p_notice_id)
  returning jsonb_build_object('id',notice_id,'title',title,'body',body,'startsAt',starts_at,'endsAt',ends_at,'active',active,'createdAt',created_at,'createdBy',created_by,'createdById',created_by_id,'updatedAt',updated_at)
  into v_before;
  if v_before is null then raise exception 'お知らせが見つかりません' using errcode='P0002'; end if;

  v_version:=public.seika_admin_notice_sync_app_state_v1150(p_id);
  v_response:=jsonb_build_object('ok',true,'conflict',false,'version',v_version,'operationId',p_operation_id,'noticeId',btrim(p_notice_id));
  insert into public.seika_admin_notice_audit_v1150(state_id,notice_id,action,operation_id,actor_id,actor_role,request_hash,before_notice,after_notice,expected_version,resulting_version)
  values(p_id,btrim(p_notice_id),'delete',p_operation_id,v_actor.actor_id,v_actor.actor_role,v_request_hash,v_before,null,p_expected_version,v_version);
  insert into public.seika_admin_notice_operations_v1150(operation_id,actor_id,action,request_hash,response) values(p_operation_id,v_actor.actor_id,'delete',v_request_hash,v_response);
  return v_response;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.delete_clerk_waste_v188(p_id text, p_expected_version bigint, p_waste_id text, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_next_data jsonb;
  v_next_version bigint;
  v_operation_uuid uuid;
begin
  v_operation_uuid := case when nullif(trim(coalesce(p_operation_id,'')),'') is null then null else public.seika_uuid_v188(p_operation_id) end;
  select * into v_profile from public.profiles where id = auth.uid() and active = true;
  if not found then raise exception 'AUTH_REQUIRED' using errcode = '42501'; end if;
  if v_profile.role <> 'clerk' then raise exception '事務員専用の削除処理です' using errcode = '42501'; end if;
  if p_id <> 'ishioka_inventory_production_v2' or nullif(trim(coalesce(p_waste_id, '')), '') is null then
    raise exception '削除対象が正しくありません' using errcode = '22023';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'message', '保存先が見つかりません'); end if;
  if v_state.version is distinct from p_expected_version then
    return jsonb_build_object('ok', false, 'conflict', true, 'message', '他端末の更新があります', 'version', v_state.version);
  end if;

  v_next_data := jsonb_set(
    coalesce(v_state.data, '{}'::jsonb),
    '{wasteRecords}',
    coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(v_state.data->'wasteRecords','[]'::jsonb)) x where x->>'id' <> p_waste_id), '[]'::jsonb),
    true
  );
  v_next_version := v_state.version + 1;

  delete from public.waste_records where id = public.seika_uuid_v188(p_waste_id);
  update public.app_state
  set data = v_next_data,
      version = v_next_version,
      updated_at = now(),
      last_operation_id = v_operation_uuid,
      last_device_meta = coalesce(p_device_meta, '{}'::jsonb),
      last_operation_meta = coalesce(p_operation_meta, '{}'::jsonb)
  where id = p_id;

  return jsonb_build_object('ok', true, 'version', v_next_version, 'updated_at', now());
end
$function$
;
CREATE OR REPLACE FUNCTION public.delete_qr_lot_v182(p_qr_key text, p_operation_id uuid, p_confirm text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lot public.qr_lots%rowtype;
  v_movement_count integer := 0;
  v_scan_count integer := 0;
  v_lot_count integer := 0;
begin
  if p_confirm is distinct from '完全削除' then
    raise exception '確認文字が一致しません' using errcode = '22023';
  end if;
  if nullif(btrim(p_qr_key), '') is null or p_operation_id is null then
    raise exception 'QRキーと操作IDは必須です' using errcode = '22023';
  end if;

  select * into v_lot
  from public.qr_lots
  where qr_key = p_qr_key
  for update;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'already_deleted', true,
      'deleted_count', 0,
      'operation_id', p_operation_id
    );
  end if;

  delete from public.qr_scan_logs
  where lot_id = v_lot.id or qr_key = v_lot.qr_key;
  get diagnostics v_scan_count = row_count;

  delete from public.qr_lot_movements
  where lot_id = v_lot.id
     or qr_key = v_lot.qr_key
     or lot_no = v_lot.lot_no;
  get diagnostics v_movement_count = row_count;

  delete from public.qr_lots
  where id = v_lot.id;
  get diagnostics v_lot_count = row_count;

  if v_lot_count <> 1 then
    raise exception 'ロット本体を削除できませんでした';
  end if;

  return jsonb_build_object(
    'ok', true,
    'already_deleted', false,
    'deleted_count', v_lot_count,
    'movement_count', v_movement_count,
    'scan_count', v_scan_count,
    'operation_id', p_operation_id,
    'qr_key', v_lot.qr_key,
    'lot_no', v_lot.lot_no,
    'item_name', v_lot.item_name
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.delete_trimming_job_v1203(p_job_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_job      public.trimming_jobs;
  v_role     text;
  v_rows     integer;
begin
  begin
    v_role := public.current_app_role();
  exception when others then
    v_role := null;
  end;
  if v_role is not null and v_role not in ('admin','worker') then
    return jsonb_build_object('ok', false, 'message', '日報の削除は管理者・青果社員のみです。');
  end if;

  select * into v_job from public.trimming_jobs where id::text = p_job_id;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'この日報は見つかりません。すでに削除された可能性があります。');
  end if;

  v_rows := public.seika_delete_trimming_job_rows_v1203(p_job_id);

  return jsonb_build_object(
    'ok', true,
    'deleted_rows', v_rows,
    'work_date', v_job.work_date,
    'item_name', v_job.source_item_name,
    'message', '日報を削除しました。'
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.disable_my_push_subscription_v1144(p_endpoint text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles;
declare v_count integer;
begin
  v_profile := public.seika_quality_push_my_profile_v1144();
  update public.web_push_subscriptions_v1144
  set active = false, updated_at = now()
  where profile_id = v_profile.id
    and endpoint = btrim(coalesce(p_endpoint, ''))
    and active;
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'disabled', v_count);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.finalize_monthly_quality_purge_v1102(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_month date:=date_trunc('month',p_target_month)::date;v_next date:=(date_trunc('month',p_target_month)+interval '1 month')::date;v_rows bigint:=0;v_photos bigint:=0;v_step bigint;
begin
  select * into v_profile from public.seika_archive_profile_v1101();if not found or v_profile.role<>'admin' then raise exception '管理者権限が必要です' using errcode='42501';end if;if v_month>=(date_trunc('month',now() at time zone 'Asia/Tokyo')-interval '3 months')::date then raise exception '3か月分の保持期間が終わっていません';end if;perform pg_advisory_xact_lock(hashtextextended('quality:'||v_month::text,1102));if not exists(select 1 from public.seika_monthly_archives where module='quality'and target_month=v_month and status='deleting'and excel_saved_at is not null)then raise exception '先に削除準備を実行してください';end if;
  if exists(select 1 from public.qr_quality_photos p join public.qr_quality_evaluations e on e.id=p.evaluation_id and e.active=true join public.qr_lots q on q.qr_key=e.qr_key and q.active=true join storage.objects o on o.bucket_id='qr-quality-photos'and o.name=p.storage_path where p.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo'))then raise exception 'Storageに品質写真が残っています。Storage APIの削除完了後に確定してください';end if;
  delete from public.qr_quality_photos p using public.qr_quality_evaluations e,public.qr_lots q where p.evaluation_id=e.id and q.qr_key=e.qr_key and p.active=true and e.active=true and q.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo');get diagnostics v_photos=row_count;
  loop delete from public.qr_quality_evaluations e using public.qr_lots q where q.qr_key=e.qr_key and q.active=true and e.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo')and not exists(select 1 from public.qr_quality_evaluations c where c.supersedes_id=e.id and c.active=true);get diagnostics v_step=row_count;v_rows:=v_rows+v_step;exit when v_step=0;end loop;
  if exists(select 1 from public.qr_quality_evaluations e join public.qr_lots q on q.qr_key=e.qr_key and q.active=true where e.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo'))then raise exception '品質評価の訂正参照が残っているため削除を確定できません';end if;update public.seika_monthly_archives set status='deleted',deleted_at=now(),deleted_by=v_profile.id,deleted_by_name=v_profile.display_name,deleted_count=v_rows,deleted_photo_count=v_photos,updated_at=now()where module='quality'and target_month=v_month;return jsonb_build_object('ok',true,'status','deleted','deleted_count',v_rows,'deleted_photo_count',v_photos);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.finalize_monthly_quality_purge_v1166(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date := date_trunc('month', p_target_month)::date;
  v_next date := (date_trunc('month', p_target_month) + interval '1 month')::date;
  v_rows bigint := 0;
  v_photos bigint := 0;
  v_step bigint := 0;
  v_archive public.seika_monthly_archives%rowtype;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or v_profile.role <> 'admin' then
    raise exception '管理者権限が必要です' using errcode = '42501';
  end if;
  if p_target_month is null then
    raise exception '対象月が不正です' using errcode = '22023';
  end if;
  if v_month >= (date_trunc('month', now() at time zone 'Asia/Tokyo') - interval '3 months')::date then
    raise exception '品質評価は直近3か月を保持します。保持期間が終わっていません' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('quality:' || v_month::text, 1102));
  select * into v_archive
  from public.seika_monthly_archives
  where module = 'quality' and target_month = v_month
  for update;

  if not found or v_archive.excel_saved_at is null then
    raise exception 'Excel保存確認済みの月だけ削除できます' using errcode = '22023';
  end if;
  if v_archive.status = 'deleted' then
    return jsonb_build_object(
      'ok', true, 'already_deleted', true, 'status', 'deleted',
      'deleted_count', coalesce(v_archive.deleted_count, 0),
      'deleted_photo_count', coalesce(v_archive.deleted_photo_count, 0)
    );
  end if;
  if v_archive.status <> 'deleting' then
    raise exception '先に削除準備を実行してください' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.qr_quality_photos p
    join public.qr_quality_evaluations e on e.id = p.evaluation_id
    join storage.objects o
      on o.bucket_id = 'qr-quality-photos' and o.name = p.storage_path
    where e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
      and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo')
  ) then
    raise exception 'Storageに品質写真が残っています。Storage APIの削除完了後に確定してください' using errcode = '22023';
  end if;

  delete from public.qr_quality_photos p
  using public.qr_quality_evaluations e
  where p.evaluation_id = e.id
    and e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
    and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo');
  get diagnostics v_photos = row_count;

  -- 同月内の訂正チェーンは子から順に削除。後月参照はprepareで阻止済み。
  loop
    delete from public.qr_quality_evaluations e
    where e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
      and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo')
      and not exists (
        select 1 from public.qr_quality_evaluations child where child.supersedes_id = e.id
      );
    get diagnostics v_step = row_count;
    v_rows := v_rows + v_step;
    exit when v_step = 0;
  end loop;

  if exists (
    select 1 from public.qr_quality_evaluations e
    where e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
      and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo')
  ) then
    raise exception '品質評価の訂正参照が残っているため削除を確定できません' using errcode = '22023';
  end if;

  update public.seika_monthly_archives
  set status = 'deleted',
      deleted_at = now(),
      deleted_by = v_profile.id,
      deleted_by_name = v_profile.display_name,
      deleted_count = v_rows,
      deleted_photo_count = v_photos,
      updated_at = now()
  where module = 'quality' and target_month = v_month;

  return jsonb_build_object(
    'ok', true, 'already_deleted', false, 'status', 'deleted',
    'deleted_count', v_rows, 'deleted_photo_count', v_photos
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.finalize_qr_quality_photo_upload_v1102(p_photo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_photo public.qr_quality_photos%rowtype;
  v_object record;
  v_actual_size bigint;
  v_actual_type text;
begin
  select * into v_profile from public.seika_quality_profile_v1102();
  if not found or v_profile.role not in ('admin','worker') then
    raise exception '品質写真の確定は管理者・青果社員のみです' using errcode = '42501';
  end if;
  select * into v_photo from public.qr_quality_photos where id=p_photo_id for update;
  if not found then
    raise exception '品質写真の予約が見つかりません';
  end if;
  if v_photo.uploaded_by<>v_profile.id then
    raise exception 'この品質写真を確定する権限がありません' using errcode = '42501';
  end if;
  if v_photo.upload_status='finalized' then
    return jsonb_build_object('ok',true,'photo_id',v_photo.id,'already_finalized',true);
  end if;

  select o.name,o.metadata into v_object
  from storage.objects o
  where o.bucket_id='qr-quality-photos' and o.name=v_photo.storage_path;
  if not found then
    raise exception '写真本体がアップロードされていません';
  end if;
  v_actual_size := nullif(v_object.metadata->>'size','')::bigint;
  v_actual_type := lower(coalesce(v_object.metadata->>'mimetype',v_object.metadata->>'contentType',''));
  if v_actual_size is null or v_actual_size<=0 or v_actual_size>358400 then
    raise exception '実ファイルが350KB以下ではありません';
  end if;
  if v_actual_type<>v_photo.content_type then
    raise exception '写真の形式が予約内容と異なります';
  end if;

  update public.qr_quality_photos
  set upload_status='finalized', declared_byte_size=v_actual_size, finalized_at=now()
  where id=v_photo.id;
  return jsonb_build_object('ok',true,'photo_id',v_photo.id,'byte_size',v_actual_size);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.finalize_qr_waste_price_v1118(p_operation_id uuid, p_qr_key text, p_waste_weight_kg numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_move public.qr_lot_movements%rowtype;
  v_lot public.qr_lots%rowtype;
  v_price jsonb;
  v_weight numeric;
  v_pack_weight numeric;
  v_unit numeric;
  v_amount numeric;
  v_match_type text;
  v_match_reason text;
  v_source_supplier text;
  v_average_count integer:=0;
begin
  v_profile:=public.trimming_require_role(array['admin','worker']);
  select * into v_move from public.qr_lot_movements
  where operation_id::text=p_operation_id::text and qr_key=p_qr_key
  order by created_at desc limit 1 for update;
  if not found then raise exception '対象のQR廃棄履歴が見つかりません' using errcode='P0002'; end if;
  if v_move.movement_type<>'廃棄' or v_move.cancelled_at is not null or v_move.reversed_operation_id is not null or public.seika_qr_operation_cancelled_v1162(v_move.operation_id::text) then
    raise exception '対象履歴は有効なQR廃棄ではありません' using errcode='22023';
  end if;
  if v_move.purchase_price_yen_per_kg is not null and v_move.waste_amount_yen is not null then
    return jsonb_build_object('ok',true,'already_finalized',true,'calculated',true,'unit_price',v_move.purchase_price_yen_per_kg,'amount',v_move.waste_amount_yen,'match_type',v_move.price_match_type);
  end if;

  select * into v_lot from public.qr_lots where id=v_move.lot_id limit 1;
  if not found then select * into v_lot from public.qr_lots where qr_key=p_qr_key limit 1; end if;
  if not found then raise exception '対象QRロットが見つかりません' using errcode='P0002'; end if;

  v_pack_weight:=public.seika_parse_kg_v1162(v_lot.pack_weight);
  v_weight:=coalesce(
    nullif(p_waste_weight_kg,0),nullif(v_move.weight,0),
    case when v_move.before_weight is not null and v_move.after_weight is not null and abs(v_move.before_weight-v_move.after_weight)>0 then abs(v_move.before_weight-v_move.after_weight) end,
    case when v_pack_weight>0 and v_move.qty>0 then round(v_pack_weight*v_move.qty,3) end
  );
  if v_weight is null or v_weight<=0 then
    return jsonb_build_object('ok',true,'calculated',false,'reason','廃棄重量を確定できません。QRロットの量目または重量を確認してください');
  end if;

  v_price:=public.resolve_trimming_purchase_price_v1117(
    v_lot.item_name,
    coalesce(v_lot.origin,''),
    coalesce(v_lot.supplier,''),
    coalesce((coalesce(v_move.occurred_at,v_move.created_at) at time zone 'Asia/Tokyo')::date,v_lot.received_date,current_date)
  );
  if not coalesce((v_price->>'found')::boolean,false) then
    return jsonb_build_object('ok',true,'calculated',false,'movement_id',v_move.id,'reason',coalesce(v_price->>'match_reason','同一品目の登録価格がありません'));
  end if;

  v_unit:=(v_price->>'price_yen_per_kg')::numeric;
  v_amount:=round(v_unit*v_weight,2);
  v_match_type:=coalesce(v_price->>'match_type','自動計算');
  v_match_reason:=coalesce(v_price->>'match_reason','QR廃棄登録時に仕入価格表から自動計算');
  v_source_supplier:=nullif(v_price->>'source_supplier','');
  v_average_count:=coalesce((v_price->>'average_count')::integer,0);

  update public.qr_lot_movements
  set purchase_price_yen_per_kg=v_unit,
      waste_amount_yen=v_amount,
      price_match_type=v_match_type,
      price_match_reason=v_match_reason,
      price_source_supplier=v_source_supplier,
      price_average_count=v_average_count,
      price_reference_date=coalesce((coalesce(v_move.occurred_at,v_move.created_at) at time zone 'Asia/Tokyo')::date,v_lot.received_date,current_date),
      price_calculated_at=now()
  where id=v_move.id;

  return jsonb_build_object('ok',true,'calculated',true,'movement_id',v_move.id,'weight_used_for_price',v_weight,'unit_price',v_unit,'amount',v_amount,'match_type',v_match_type,'reason',v_match_reason,'average_count',v_average_count);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_app_state_v187(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  r public.app_state%rowtype;
  safe_data jsonb;
begin
  if not public.is_active_user() then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select * into r
  from public.app_state
  where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;

  safe_data := coalesce(r.data, '{}'::jsonb);
  safe_data := jsonb_set(
    safe_data,
    '{users}',
    coalesce((
      select jsonb_agg(
        (u - 'password' - 'passwordBaseReset')
        order by u->>'id'
      )
      from jsonb_array_elements(coalesce(safe_data->'users', '[]'::jsonb)) u
    ), '[]'::jsonb),
    true
  );

  return jsonb_build_object(
    'ok', true,
    'id', r.id,
    'data', safe_data,
    'version', r.version,
    'updated_at', r.updated_at
  );
end
$function$
;
CREATE OR REPLACE FUNCTION public.get_fifo_candidates_v1136(p_qr_key text, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;lim integer:=greatest(1,least(coalesce(p_limit,10),50));begin a:=public.seika_fifo_assess_lot_v1136(p_qr_key);if coalesce((a->>'ok')::boolean,false)=false then return a;end if;return a||jsonb_build_object('mode',public.seika_v1136_get_fifo_mode(),'display_limit',lim,'candidates',coalesce((select jsonb_agg(x.value order by(x.value->>'candidate_rank')::integer)from jsonb_array_elements(coalesce(a->'candidates','[]'::jsonb))with ordinality x(value,n)where x.n<=lim),'[]'::jsonb));end $function$
;
CREATE OR REPLACE FUNCTION public.get_inventory_loss_cockpit_v1136(p_from date DEFAULT (CURRENT_DATE - 29), p_to date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;wr jsonb;qr jsonb;begin v:=public.seika_v1136_require_roles(array['admin','worker','buyer','clerk']);if p_from is null or p_to is null or p_from>p_to or (p_to-p_from+1)not between 1 and 366 then raise exception '対象期間は1〜366日（両端を含む）で指定してください';end if;
 with w as(select x.*, (select count(*)from public.qr_lot_movements m where m.movement_type='廃棄'and m.cancelled_at is null and m.occurred_at::date=x.waste_date and m.item_name is not distinct from x.item_name and m.qty is not distinct from x.qty and coalesce(nullif(m.unit,''),'')=coalesce(nullif(x.data->>'unit',''),'') and m.weight is not null and nullif(x.data->>'weight','')is not null and m.weight::text=x.data->>'weight') possible_duplicate_count from public.waste_records x where x.waste_date between p_from and p_to)select coalesce(jsonb_agg(jsonb_build_object('source','waste_records','source_id',id,'occurred_date',waste_date,'item_name',item_name,'unit',coalesce(nullif(data->>'unit',''),'不明'),'quantity',qty,'declared_weight',nullif(data->>'weight',''),'unit_price',unit_price,'amount_yen',amount,'amount_status',case when amount is not null then 'amount_from_record' when unit_price is null then 'unassessed_unit_price_and_amount' else 'amount_missing_despite_unit_price'end,'price_source','waste_records.amount / waste_records.unit_price','unassessed_reason',case when amount is not null then null when unit_price is null then '通常廃棄レコードにamount・unit_priceがありません'else'通常廃棄レコードにamountがありません'end,'possible_duplicate_count',possible_duplicate_count,'possible_duplicate_note',case when possible_duplicate_count>0 then '日付・品目・数量・単位・記録重量がQR廃棄と厳格一致する確認候補。自動統合・除外はしていません'end)order by waste_date,id),'[]'::jsonb)into wr from w;
 with q as(select x.*, (select count(*)from public.waste_records w where w.waste_date=x.occurred_at::date and w.item_name is not distinct from x.item_name and w.qty is not distinct from x.qty and coalesce(nullif(w.data->>'unit',''),'')=coalesce(nullif(x.unit,''),'') and x.weight is not null and nullif(w.data->>'weight','')is not null and w.data->>'weight'=x.weight::text) possible_duplicate_count from public.qr_lot_movements x where x.movement_type='廃棄'and x.cancelled_at is null and x.occurred_at::date between p_from and p_to)select coalesce(jsonb_agg(jsonb_build_object('source','qr_lot_movements','source_id',id,'occurred_date',occurred_at::date,'item_name',item_name,'origin',origin,'supplier',supplier,'unit',coalesce(nullif(unit,''),'不明'),'quantity',qty,'weight',weight,'unit_price',purchase_price_yen_per_kg,'amount_yen',waste_amount_yen,'amount_status',case when waste_amount_yen is not null then 'amount_from_qr_record' when purchase_price_yen_per_kg is null then 'unassessed_unit_price_and_amount' else 'amount_missing_despite_unit_price'end,'price_source',jsonb_build_object('match_type',price_match_type,'match_reason',price_match_reason,'source_supplier',price_source_supplier,'reference_date',price_reference_date),'unassessed_reason',case when waste_amount_yen is not null then null when purchase_price_yen_per_kg is null then 'QR廃棄に確定単価・金額がありません'else'QR廃棄に確定金額がありません'end,'possible_duplicate_count',possible_duplicate_count,'possible_duplicate_note',case when possible_duplicate_count>0 then '日付・品目・数量・単位・記録重量が通常廃棄と厳格一致する確認候補。自動統合・除外はしていません'end)order by occurred_at,id),'[]'::jsonb)into qr from q;
 return jsonb_build_object('ok',true,'from',p_from,'to',p_to,'period_days',p_to-p_from+1,'aggregation_prohibited',true,'note','通常廃棄とQR廃棄は別ソースです。共通イベントIDがないため合計・自動重複排除をしません。possible_duplicateは確認候補のみです。','waste_records_rows',wr,'qr_waste_movement_rows',qr);end $function$
;
CREATE OR REPLACE FUNCTION public.get_monthly_quality_export_v1102(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_month date:=date_trunc('month',p_target_month)::date;v_next date:=(date_trunc('month',p_target_month)+interval '1 month')::date;v_rows jsonb;
begin
 select * into v_profile from public.seika_archive_profile_v1101();if not found or not public.seika_archive_module_allowed_v1101('quality',v_profile.role)then raise exception '品質評価Excelを出力する権限がありません' using errcode='42501';end if;if v_month>=date_trunc('month',now() at time zone 'Asia/Tokyo')::date then raise exception '品質評価の月次Excelは前月以前だけ出力できます';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'qr_key',e.qr_key,'lot_id',e.lot_id,'lot_no',e.lot_no,'item_name',e.item_name,'grade',e.grade,'issues',e.issues,'memo',e.memo,'correction_reason',e.correction_reason,'evaluated_at',e.evaluated_at,'evaluated_by_name',e.evaluated_by_name,'supersedes_id',e.supersedes_id,'is_superseded',exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and n.active=true),'photos',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'storage_path',p.storage_path,'content_type',p.content_type,'byte_size',p.declared_byte_size,'created_at',p.created_at)order by p.created_at)from public.qr_quality_photos p where p.evaluation_id=e.id and p.upload_status='finalized' and p.active=true),'[]'::jsonb))order by e.evaluated_at,e.created_at),'[]'::jsonb)into v_rows from public.qr_quality_evaluations e join public.qr_lots q on q.qr_key=e.qr_key and q.active=true where e.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo');return jsonb_build_object('ok',true,'target_month',to_char(v_month,'YYYY-MM'),'evaluations',v_rows);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_monthly_trimming_archive_v1116(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date := date_trunc('month',p_target_month)::date;
  v_next date := (date_trunc('month',p_target_month)+interval '1 month')::date;
  v_jobs jsonb;
  v_prices jsonb;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or not public.seika_archive_module_allowed_v1101('trimming',v_profile.role) then
    raise exception '歩留まり月次Excelを出力する権限がありません' using errcode='42501';
  end if;
  if v_month >= date_trunc('month',current_date)::date then
    raise exception '月次保存の対象は前月以前です';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'job',to_jsonb(j),
    'lots',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at) from public.trimming_job_lots l where l.trimming_job_id=j.id),'[]'::jsonb),
    'outputs',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at) from public.trimming_job_outputs o where o.trimming_job_id=j.id),'[]'::jsonb)
  ) order by j.work_date,j.created_at),'[]'::jsonb)
  into v_jobs from public.trimming_jobs j
  where j.work_date>=v_month and j.work_date<v_next;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.week_start,p.item_name,p.origin,p.supplier),'[]'::jsonb)
  into v_prices from public.purchase_prices p
  where p.week_start>=v_month and p.week_start<v_next;

  return jsonb_build_object('ok',true,'target_month',to_char(v_month,'YYYY-MM'),'jobs',v_jobs,'prices',v_prices);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_my_profile()
 RETURNS TABLE(id uuid, legacy_user_id text, display_name text, role text, active boolean, must_change_password boolean, display_settings jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select p.id, p.legacy_user_id, p.display_name, p.role, p.active,
         p.must_change_password, p.display_settings
  from public.profiles p
  where p.id = auth.uid()
    and p.active = true
  limit 1
$function$
;
CREATE OR REPLACE FUNCTION public.get_purchase_prices(p_week_start date DEFAULT NULL::date)
 RETURNS SETOF purchase_prices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.trimming_require_role(array['admin','worker','buyer','sales','clerk','viewer','office_viewer']);
  return query select pp.* from public.purchase_prices pp
    where p_week_start is null or pp.week_start = public.trimming_week_start(p_week_start)
    order by pp.week_start desc, pp.item_name, pp.origin, pp.supplier;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_push_notification_config_v1144()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles;
begin
  v_profile := public.seika_quality_push_my_profile_v1144();
  return jsonb_build_object(
    'ok', true,
    'role', v_profile.role,
    'active', v_profile.active,
    'subscription_count', (
      select count(*) from public.web_push_subscriptions_v1144 s
      where s.profile_id = v_profile.id and s.active
    )
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_rule_based_decisions_v1136(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;r jsonb;lim integer:=greatest(1,least(coalesce(p_limit,100),500));begin v:=public.seika_v1136_require_roles(array['admin','worker','buyer','clerk']);with latest as(select distinct on(e.qr_key)e.qr_key,e.id,e.grade from public.qr_quality_evaluations e where e.active=true and e.invalidated_at is null and e.invalidated_by_lot_delete=false and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and n.active=true and n.invalidated_at is null and n.invalidated_by_lot_delete=false)order by e.qr_key,e.evaluated_at desc,e.created_at desc,e.id desc),pm as(select q.*,l.id evaluation_id,l.grade,h.active held,p.id policy_id,p.attention_days,p.warning_days,p.critical_days,p.quality_review_requires_confirmation,row_number()over(partition by q.id order by case when nullif(btrim(coalesce(p.item_id,'')),'')is not null then 0 else 1 end,p.effective_from desc,p.created_at desc)pr from public.qr_lots q left join latest l on l.qr_key=q.qr_key left join public.seika_fifo_lot_holds_v1136 h on h.lot_id=q.id and h.active left join public.seika_item_aging_policies_v1136 p on p.active and p.effective_from<=current_date and(p.effective_to is null or p.effective_to>=current_date)and((nullif(btrim(coalesce(q.item_id,'')),'')is not null and nullif(btrim(coalesce(p.item_id,'')),'')=nullif(btrim(coalesce(q.item_id,'')),'') )or(nullif(btrim(coalesce(q.item_id,'')),'')is null and nullif(btrim(coalesce(p.item_id,'')),'')is null and nullif(btrim(coalesce(p.item_name,'')),'')=nullif(btrim(coalesce(q.item_name,'')),'')))where q.active and q.status='在庫あり'and q.current_qty>0),a as(select *,greatest(0,current_date-received_date)age_days,case when held then '保留解除または出庫可否を管理者が確認'when grade='bad'then'品質不良のため出庫候補外。品質確認・処置を実施'when grade='review'and coalesce(quality_review_requires_confirmation,true)then'要確認品質。出庫前に品質確認'when policy_id is null then'滞留基準未設定。管理者が品目別基準を設定'when greatest(0,current_date-received_date)>=critical_days then'重大滞留。処置を利用者が判断'when greatest(0,current_date-received_date)>=warning_days then'滞留警告。優先出庫を検討'when greatest(0,current_date-received_date)>=attention_days then'滞留注意。FIFO候補を確認'else'通常監視'end action from pm where pr=1 or pr is null)select coalesce(jsonb_agg(jsonb_build_object('lot_id',id,'qr_key',qr_key,'lot_no',lot_no,'item_id',item_id,'item_name',item_name,'received_date',received_date,'current_qty',current_qty,'unit',unit,'action',action,'rule_basis',jsonb_build_object('rule_version','v1.136','age_days',age_days,'quality_evaluation_id',evaluation_id,'quality_status',coalesce(grade,'unassessed'),'hold_active',coalesce(held,false),'policy_id',policy_id,'automatic_action',false))order by received_date,id),'[]'::jsonb)into r from(select*from a order by received_date,id limit lim)s;return jsonb_build_object('ok',true,'automatic_action',false,'message','これはルール根拠付き判断支援です。在庫変更・出庫・廃棄は実行しません。','rows',r);end $function$
;
CREATE OR REPLACE FUNCTION public.get_seika_v1136_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;begin v:=public.seika_v1136_require_roles(array['admin']);return jsonb_build_object('ok',true,'mode',public.seika_v1136_get_fifo_mode(),'is_admin',(v.role='admin'),'policies',(select coalesce(jsonb_agg(to_jsonb(p)order by p.item_name,p.item_id,p.effective_from desc),'[]'::jsonb)from public.seika_item_aging_policies_v1136 p),'holds',(select coalesce(jsonb_agg(jsonb_build_object('lot_id',h.lot_id,'hold_reason',h.hold_reason,'held_at',h.held_at,'qr_key',q.qr_key,'lot_no',q.lot_no,'item_name',q.item_name)),'[]'::jsonb)from public.seika_fifo_lot_holds_v1136 h join public.qr_lots q on q.id=h.lot_id where h.active),'pending_transitions',(select coalesce(jsonb_agg(to_jsonb(t)order by t.requested_at desc),'[]'::jsonb)from public.seika_fifo_mode_transition_approvals_v1136 t where t.status='pending'));end $function$
;
CREATE OR REPLACE FUNCTION public.get_supplier_quality_analysis_v1136(p_from date DEFAULT (CURRENT_DATE - 89), p_to date DEFAULT CURRENT_DATE, p_supplier text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;si jsonb;so jsonb;begin v:=public.seika_v1136_require_roles(array['admin','worker','buyer','clerk']);if p_from is null or p_to is null or p_from>p_to or(p_to-p_from+1)not between 1 and 366 then raise exception '対象期間は1〜366日（両端を含む）で指定してください';end if;
 with latest as(select distinct on(e.qr_key)e.qr_key,e.id,e.grade,e.evaluated_at from public.qr_quality_evaluations e where e.active=true and e.invalidated_at is null and e.invalidated_by_lot_delete=false and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and n.active=true and n.invalidated_at is null and n.invalidated_by_lot_delete=false)order by e.qr_key,e.evaluated_at desc,e.created_at desc,e.id desc),base as(select q.supplier,q.cooperative_name,q.item_id,q.item_name,l.grade from latest l join public.qr_lots q on q.qr_key=l.qr_key where l.evaluated_at::date between p_from and p_to and(nullif(btrim(coalesce(p_supplier,'')),'')is null or q.supplier=p_supplier)),agg as(select supplier,cooperative_name,item_id,item_name,count(*)evaluation_count,count(*)filter(where grade='good')good_count,count(*)filter(where grade='review')review_count,count(*)filter(where grade='bad')bad_count,round(count(*)filter(where grade='good')::numeric/nullif(count(*),0),4)good_ratio,round(count(*)filter(where grade='review')::numeric/nullif(count(*),0),4)review_ratio,round(count(*)filter(where grade='bad')::numeric/nullif(count(*),0),4)bad_ratio from base group by supplier,cooperative_name,item_id,item_name)select coalesce(jsonb_agg(to_jsonb(agg)order by supplier,cooperative_name,item_name,item_id),'[]'::jsonb)into si from agg;
 with latest as(select distinct on(e.qr_key)e.qr_key,e.id,e.grade,e.evaluated_at from public.qr_quality_evaluations e where e.active=true and e.invalidated_at is null and e.invalidated_by_lot_delete=false and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and n.active=true and n.invalidated_at is null and n.invalidated_by_lot_delete=false)order by e.qr_key,e.evaluated_at desc,e.created_at desc,e.id desc),base as(select q.supplier,q.cooperative_name,l.grade from latest l join public.qr_lots q on q.qr_key=l.qr_key where l.evaluated_at::date between p_from and p_to and(nullif(btrim(coalesce(p_supplier,'')),'')is null or q.supplier=p_supplier)),agg as(select supplier,cooperative_name,count(*)evaluation_count,count(*)filter(where grade='good')good_count,count(*)filter(where grade='review')review_count,count(*)filter(where grade='bad')bad_count,round(count(*)filter(where grade='good')::numeric/nullif(count(*),0),4)good_ratio,round(count(*)filter(where grade='review')::numeric/nullif(count(*),0),4)review_ratio,round(count(*)filter(where grade='bad')::numeric/nullif(count(*),0),4)bad_ratio from base group by supplier,cooperative_name)select coalesce(jsonb_agg(to_jsonb(agg)order by supplier,cooperative_name),'[]'::jsonb)into so from agg;
 return jsonb_build_object('ok',true,'from',p_from,'to',p_to,'period_days',p_to-p_from+1,'ranking',false,'normalization',false,'note','仕入先表記は登録済みの正式値をそのまま返します。自動名寄せ・順位付け・優劣の自動判定はしません。','supplier_item_sections',si,'supplier_overall_sections',so);end $function$
;
CREATE OR REPLACE FUNCTION public.get_trimming_jobs(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(job jsonb, lots jsonb, outputs jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.trimming_require_role(array['admin','worker','buyer','sales','clerk','viewer','office_viewer']);
  return query
  select to_jsonb(j),
         coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at) from public.trimming_job_lots l where l.trimming_job_id=j.id), '[]'::jsonb),
         coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at) from public.trimming_job_outputs o where o.trimming_job_id=j.id), '[]'::jsonb)
  from public.trimming_jobs j
  where (p_from is null or j.work_date >= p_from) and (p_to is null or j.work_date <= p_to)
  order by j.work_date desc, j.created_at desc;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_app_state_update_v185()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.assert_app_state_not_rollback_v185(
    old.data,
    new.data,
    coalesce(new.last_operation_meta, '{}'::jsonb)
  );
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.guard_seika_qr_write_v187()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  r text;
  old_safe jsonb;
  new_safe jsonb;
begin
  r := public.current_app_role();
  if r is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;

  if tg_op='DELETE' then
    if r <> 'admin' then
      raise exception 'ADMIN_REQUIRED' using errcode='42501';
    end if;
    return old;
  end if;

  if r in ('admin','worker') then
    return new;
  end if;

  if r='clerk' then
    if tg_table_name='qr_lot_movements' and tg_op='INSERT'
       and new.movement_type='廃棄'
       and coalesce(new.qty,0)>0 then
      return new;
    end if;

    if tg_table_name='qr_lots' and tg_op='UPDATE'
       and coalesce(new.current_qty,0) < coalesce(old.current_qty,0)
       and coalesce(new.current_qty,0) >= 0 then
      old_safe := to_jsonb(old) - array['current_qty','current_weight','status','updated_at'];
      new_safe := to_jsonb(new) - array['current_qty','current_weight','status','updated_at'];
      if old_safe = new_safe then
        return new;
      end if;
    end if;
  end if;

  raise exception 'QR_WRITE_FORBIDDEN' using errcode='42501';
end
$function$
;
CREATE OR REPLACE FUNCTION public.has_any_role(allowed_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select coalesce(public.current_app_role() = any(allowed_roles), false)
$function$
;
CREATE OR REPLACE FUNCTION public.is_active_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.active = true
  )
$function$
;
CREATE OR REPLACE FUNCTION public.list_active_registered_users_v1178()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_users jsonb;
begin
  v_profile := public.seika_v1144_require_active_profile();
  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id', id,
    'legacy_user_id', legacy_user_id,
    'display_name', display_name,
    'active', active
  ) order by display_name, legacy_user_id), '[]'::jsonb)
  into v_users
  from public.profiles
  where active = true
    and nullif(btrim(coalesce(legacy_user_id, '')), '') is not null
    and nullif(btrim(coalesce(display_name, '')), '') is not null;
  return jsonb_build_object('ok', true, 'users', v_users);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_active_registered_users_v1179()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_users jsonb;
begin
  -- ログイン済みかつ有効なプロフィールであることを既存の認可関数で確認する。
  v_profile := public.seika_v1144_require_active_profile();

  with source_rows as (
    select
      p.id as profile_id,
      lower(btrim(p.legacy_user_id)) as legacy_id_key,
      regexp_replace(translate(btrim(p.display_name), '（）', '()'), '[[:space:]　]', '', 'g') as display_name_key,
      btrim(p.display_name) as original_display_name
    from public.profiles p
    where p.active = true
      and nullif(btrim(coalesce(p.legacy_user_id, '')), '') is not null
      and nullif(btrim(coalesce(p.display_name, '')), '') is not null
  ), normalized as (
    select
      profile_id,
      case
        when legacy_id_key in ('seki_hiroshi', 'seki') or display_name_key in ('関(宏)', '関宏世') then 'seki_hiroshi'
        when legacy_id_key in ('saito_dai', 'saito') or display_name_key in ('斎藤(大)', '斎藤大明') then 'saito_dai'
        when legacy_id_key = 'sakamoto' or display_name_key in ('坂本', '坂本美穂') then 'sakamoto'
        when legacy_id_key = 'yoshida' or display_name_key in ('吉田', '吉田智彦') then 'yoshida'
        when legacy_id_key = 'araki' or display_name_key in ('荒木', '荒木貴裕') then 'araki'
        else legacy_id_key
      end as canonical_legacy_user_id,
      case
        when legacy_id_key in ('seki_hiroshi', 'seki') or display_name_key in ('関(宏)', '関宏世') then '関 宏世'
        when legacy_id_key in ('saito_dai', 'saito') or display_name_key in ('斎藤(大)', '斎藤大明') then '斎藤 大明'
        when legacy_id_key = 'sakamoto' or display_name_key in ('坂本', '坂本美穂') then '坂本 美穂'
        when legacy_id_key = 'yoshida' or display_name_key in ('吉田', '吉田智彦') then '吉田 智彦'
        when legacy_id_key = 'araki' or display_name_key in ('荒木', '荒木貴裕') then '荒木 貴裕'
        else original_display_name
      end as formal_display_name,
      legacy_id_key
    from source_rows
  ), ranked as (
    select
      *,
      row_number() over (
        partition by canonical_legacy_user_id
        -- canonical IDのプロフィールを優先し、同一人物の旧ID/略称プロフィールは返却しない。
        order by case when legacy_id_key = canonical_legacy_user_id then 0 else 1 end, profile_id
      ) as rn
    from normalized
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id', profile_id,
    'legacy_user_id', canonical_legacy_user_id,
    'display_name', formal_display_name,
    'active', true
  ) order by formal_display_name, canonical_legacy_user_id), '[]'::jsonb)
  into v_users
  from ranked
  where rn = 1;

  return jsonb_build_object('ok', true, 'users', v_users);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_monthly_archives_v1101(p_module text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_rows jsonb;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or not public.seika_archive_module_allowed_v1101(p_module, v_profile.role) then
    raise exception 'この月次履歴を確認する権限がありません' using errcode='42501';
  end if;

  if p_module = 'waste' then
    with counts as (
      select date_trunc('month', waste_date)::date target_month, count(*)::bigint row_count
      from public.waste_records
      where waste_date is not null
      group by 1
    ), months as (
      select target_month from counts
      union
      select target_month from public.seika_monthly_archives where module=p_module
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'target_month',to_char(m.target_month,'YYYY-MM'),
      'row_count',coalesce(c.row_count,a.row_count,0),
      'status',coalesce(a.status,'pending'),
      'file_name',a.file_name,
      'excel_created_at',a.excel_created_at,
      'excel_created_by_name',a.excel_created_by_name,
      'excel_saved_at',a.excel_saved_at,
      'excel_saved_by_name',a.excel_saved_by_name,
      'deleted_at',a.deleted_at,
      'deleted_by_name',a.deleted_by_name,
      'deleted_count',a.deleted_count
    ) order by m.target_month desc),'[]'::jsonb)
    into v_rows
    from months m
    left join counts c using(target_month)
    left join public.seika_monthly_archives a on a.module=p_module and a.target_month=m.target_month;
  elsif p_module = 'qr' then
    with counts as (
      select date_trunc('month',coalesce((to_jsonb(q)->>'occurred_at')::timestamptz,q.created_at) at time zone 'Asia/Tokyo')::date target_month,
             count(*)::bigint row_count
      from public.qr_lot_movements q
      group by 1
    ), months as (
      select target_month from counts
      union
      select target_month from public.seika_monthly_archives where module=p_module
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'target_month',to_char(m.target_month,'YYYY-MM'),
      'row_count',coalesce(c.row_count,a.row_count,0),
      'status',coalesce(a.status,'pending'),
      'file_name',a.file_name,
      'excel_created_at',a.excel_created_at,
      'excel_created_by_name',a.excel_created_by_name,
      'excel_saved_at',a.excel_saved_at,
      'excel_saved_by_name',a.excel_saved_by_name,
      'deleted_at',a.deleted_at,
      'deleted_by_name',a.deleted_by_name,
      'deleted_count',a.deleted_count
    ) order by m.target_month desc),'[]'::jsonb)
    into v_rows
    from months m
    left join counts c using(target_month)
    left join public.seika_monthly_archives a on a.module=p_module and a.target_month=m.target_month;
  elsif p_module = 'trimming' then
    with counts as (
      select date_trunc('month', work_date)::date target_month, count(*)::bigint row_count
      from public.trimming_jobs group by 1
      union all
      select date_trunc('month', week_start)::date target_month, count(*)::bigint row_count
      from public.purchase_prices group by 1
    ), totals as (
      select target_month, sum(row_count)::bigint row_count from counts group by target_month
    ), months as (
      select target_month from totals
      union
      select target_month from public.seika_monthly_archives where module=p_module
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'target_month',to_char(m.target_month,'YYYY-MM'),
      'row_count',coalesce(c.row_count,a.row_count,0),
      'status',coalesce(a.status,'pending'),
      'file_name',a.file_name,
      'excel_created_at',a.excel_created_at,
      'excel_created_by_name',a.excel_created_by_name,
      'excel_saved_at',a.excel_saved_at,
      'excel_saved_by_name',a.excel_saved_by_name,
      'deleted_at',a.deleted_at,
      'deleted_by_name',a.deleted_by_name,
      'deleted_count',a.deleted_count
    ) order by m.target_month desc),'[]'::jsonb)
    into v_rows
    from months m
    left join totals c using(target_month)
    left join public.seika_monthly_archives a on a.module=p_module and a.target_month=m.target_month;
  else
    raise exception '対象区分が不正です';
  end if;

  return jsonb_build_object('ok',true,'module',p_module,'archives',v_rows);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_monthly_quality_archives_v1102()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype; v_rows jsonb;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or not public.seika_archive_module_allowed_v1101('quality',v_profile.role) then
    raise exception '品質評価の月次履歴を確認する権限がありません' using errcode='42501';
  end if;
  with counts as (
    select public.seika_quality_month_v1102(e.evaluated_at) target_month,
           count(distinct e.id)::bigint row_count,
           count(p.id) filter (where p.upload_status='finalized')::bigint photo_count,
           count(p.id) filter (where p.upload_status='pending')::bigint pending_photo_count
    from public.qr_quality_evaluations e
    left join public.qr_quality_photos p on p.evaluation_id=e.id
    group by 1
  ), months as (
    select target_month from counts
    union
    select target_month from public.seika_monthly_archives where module='quality'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'target_month',to_char(m.target_month,'YYYY-MM'),
    'row_count',coalesce(c.row_count,a.row_count,0),
    'photo_count',coalesce(c.photo_count,a.photo_count,0),
    'pending_photo_count',coalesce(c.pending_photo_count,0),
    'status',coalesce(a.status,'pending'),'file_name',a.file_name,
    'excel_created_at',a.excel_created_at,'excel_created_by_name',a.excel_created_by_name,
    'excel_saved_at',a.excel_saved_at,'excel_saved_by_name',a.excel_saved_by_name,
    'deleted_at',a.deleted_at,'deleted_by_name',a.deleted_by_name,
    'deleted_count',a.deleted_count,'deleted_photo_count',a.deleted_photo_count
  ) order by m.target_month desc),'[]'::jsonb) into v_rows
  from months m left join counts c using(target_month)
  left join public.seika_monthly_archives a on a.module='quality' and a.target_month=m.target_month;
  return jsonb_build_object('ok',true,'module','quality','archives',v_rows);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_monthly_quality_archives_v1166()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_rows jsonb;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or not public.seika_archive_module_allowed_v1101('quality', v_profile.role) then
    raise exception '品質評価の月次履歴を確認する権限がありません' using errcode = '42501';
  end if;

  with excel_counts as (
    select
      public.seika_quality_month_v1102(e.evaluated_at) as target_month,
      count(distinct e.id)::bigint as row_count,
      count(p.id) filter (where p.upload_status = 'finalized')::bigint as photo_count,
      count(p.id) filter (where p.upload_status = 'pending')::bigint as pending_photo_count
    from public.qr_quality_evaluations e
    left join public.qr_quality_photos p
      on p.evaluation_id = e.id and p.active = true
    where e.active = true
    group by 1
  ), cleanup_counts as (
    select
      public.seika_quality_month_v1102(e.evaluated_at) as target_month,
      count(distinct e.id)::bigint as cleanup_row_count,
      count(p.id)::bigint as cleanup_photo_count
    from public.qr_quality_evaluations e
    left join public.qr_quality_photos p on p.evaluation_id = e.id
    group by 1
  ), months as (
    select target_month from excel_counts
    union
    select target_month from cleanup_counts
    union
    select target_month from public.seika_monthly_archives where module = 'quality'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'target_month', to_char(m.target_month, 'YYYY-MM'),
    'row_count', coalesce(ec.row_count, a.row_count, 0),
    'photo_count', coalesce(ec.photo_count, a.photo_count, 0),
    'pending_photo_count', coalesce(ec.pending_photo_count, 0),
    'cleanup_row_count', coalesce(cc.cleanup_row_count, 0),
    'cleanup_photo_count', coalesce(cc.cleanup_photo_count, 0),
    'retention_months', 3,
    'purge_eligible', (
      a.status in ('excel_saved', 'deleting')
      and a.excel_saved_at is not null
      and m.target_month < (date_trunc('month', now() at time zone 'Asia/Tokyo') - interval '3 months')::date
    ),
    'status', coalesce(a.status, 'pending'),
    'file_name', a.file_name,
    'excel_created_at', a.excel_created_at,
    'excel_created_by_name', a.excel_created_by_name,
    'excel_saved_at', a.excel_saved_at,
    'excel_saved_by_name', a.excel_saved_by_name,
    'deleted_at', a.deleted_at,
    'deleted_by_name', a.deleted_by_name,
    'deleted_count', a.deleted_count,
    'deleted_photo_count', a.deleted_photo_count
  ) order by m.target_month desc), '[]'::jsonb)
  into v_rows
  from months m
  left join excel_counts ec using (target_month)
  left join cleanup_counts cc using (target_month)
  left join public.seika_monthly_archives a
    on a.module = 'quality' and a.target_month = m.target_month;

  return jsonb_build_object('ok', true, 'module', 'quality', 'retention_months', 3, 'archives', v_rows);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_my_unacknowledged_low_quality_evaluations_v1103(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
  v_rows jsonb;
begin
  select p.* into v_profile from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if not found or v_profile.role not in ('admin','buyer') then raise exception '低評価アラートを閲覧する権限がありません' using errcode='42501'; end if;
  with latest as (
    select e.*,q.id as current_lot_id,coalesce(q.item_name,e.item_name) as current_item_name,
      public.seika_quality_buyer_context_for_lot_v1159(q.id) as buyer_context
    from public.qr_quality_evaluations e
    join lateral (
      select lot.* from public.qr_lots lot
      where (e.lot_id is not null and lot.id::text=e.lot_id::text) or lot.qr_key=e.qr_key
      order by case when e.lot_id is not null and lot.id::text=e.lot_id::text then 0 else 1 end,coalesce(lot.active,true) desc,lot.created_at desc,lot.id desc
      limit 1
    ) q on true
    where e.grade in ('review','bad') and e.acknowledged_at is null and coalesce(e.active,true)=true
      and to_jsonb(e)->>'invalidated_at' is null
      and coalesce((to_jsonb(e)->>'invalidated_by_lot_delete')::boolean,false)=false
      and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and coalesce(n.active,true)=true and to_jsonb(n)->>'invalidated_at' is null and coalesce((to_jsonb(n)->>'invalidated_by_lot_delete')::boolean,false)=false)
  ), allowed as (
    select * from latest l
    where v_profile.role='admin' or exists(select 1 from jsonb_array_elements(l.buyer_context->'acknowledger_profile_ids') x where x#>>'{}'=v_profile.id::text)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'qr_key',qr_key,'lot_id',lot_id,'lot_no',lot_no,'item_name',current_item_name,'grade',grade,'evaluated_at',evaluated_at,'buyers',buyer_context->'buyers','buyer_source',buyer_context->>'buyer_source') order by case grade when 'bad' then 1 else 2 end,evaluated_at desc),'[]'::jsonb)
  into v_rows from (select * from allowed order by case grade when 'bad' then 1 else 2 end,evaluated_at desc limit v_limit) s;
  return jsonb_build_object('ok',true,'evaluations',v_rows);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_qr_outbound_history_v1144(p_destination text, p_work_date date, p_include_cancelled boolean DEFAULT false, p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_limit int := greatest(1, least(coalesce(p_limit, 500), 500));
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_date date := coalesce(p_work_date, (now() at time zone 'Asia/Tokyo')::date);
  v_result jsonb;
begin
  v_profile := public.seika_v1144_require_active_profile();

  with base as (
    select
      q.*,
      coalesce(q.occurred_at, q.created_at) as event_at,
      (q.cancelled_at is not null
        or q.reversed_operation_id is not null
        or public.seika_v1144_qr_operation_cancelled(q.operation_id)) as is_cancelled,
      coalesce(q.container_type, l.container_type) as resolved_container_type,
      l.pack_weight as resolved_pack_weight,
      coalesce(q.lot_no, l.lot_no) as resolved_lot_no,
      coalesce(q.qr_key, l.qr_key) as resolved_qr_key
    from public.qr_lot_movements q
    left join lateral (
      select
        l1.container_type,
        l1.pack_weight,
        l1.lot_no,
        l1.qr_key
      from public.qr_lots l1
      where (
        q.lot_id is not null
        and l1.id::text = q.lot_id::text
      ) or (
        q.lot_id is null
        and l1.qr_key = q.qr_key
      )
      order by l1.id::text
      limit 1
    ) l on true
    where q.movement_type = '出庫'
  ), filtered as (
    select * from base
    where (event_at at time zone 'Asia/Tokyo')::date = v_date
      and (nullif(btrim(coalesce(p_destination, '')), '') is null or destination = p_destination)
      and (p_include_cancelled or not is_cancelled)
  ), resolved as (
    select
      *,
      case
        when weight is not null then weight
        when resolved_container_type in ('網コンテナ', '鉄コンテナ', 'パレテーナ') then null
        when unit ~* '(^|\s)(kg|㎏|キロ)(\s|$)' then qty
        when nullif(regexp_replace(coalesce(resolved_pack_weight::text, ''), '[^0-9.]', '', 'g'), '') is not null
          then qty * nullif(regexp_replace(coalesce(resolved_pack_weight::text, ''), '[^0-9.]', '', 'g'), '')::numeric
        else null
      end as kg,
      resolved_container_type in ('網コンテナ', '鉄コンテナ', 'パレテーナ') as is_large
    from filtered
  ), counted as (
    select count(*)::bigint as total_count from filtered
  ), summary_src as (
    select
      item_name,
      unit,
      sum(qty) as qty,
      sum(kg) as weight_kg,
      count(*) filter (where kg is null and is_large) as unconfirmed_large_count,
      count(*) filter (where kg is null and not is_large) as unconvertible_normal_count
    from resolved
    group by item_name, unit
  ), summary_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'item_name', item_name,
      'unit', unit,
      'qty', qty,
      'weight_kg', weight_kg,
      'unconfirmed_large_count', unconfirmed_large_count,
      'unconvertible_normal_count', unconvertible_normal_count
    ) order by item_name, unit), '[]'::jsonb) as summary_rows
    from summary_src
  ), page as (
    select * from filtered
    order by event_at, id
    limit v_limit offset v_offset
  ), rows_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id,
      'operation_id', operation_id,
      'occurred_at', event_at,
      'destination', destination,
      'item_name', item_name,
      'qty', qty,
      'unit', unit,
      'weight', weight,
      'lot_no', resolved_lot_no,
      'qr_key', resolved_qr_key,
      'container_type', resolved_container_type,
      'pack_weight', resolved_pack_weight,
      'user_name', user_name,
      'memo', memo,
      'is_cancelled', is_cancelled
    ) order by event_at, id), '[]'::jsonb) as rows
    from page
  ), dest_src as (
    select distinct destination
    from public.qr_lot_movements
    where movement_type = '出庫'
      and nullif(btrim(coalesce(destination, '')), '') is not null
  ), dest_json as (
    select coalesce(jsonb_agg(destination order by destination), '[]'::jsonb) as destinations
    from dest_src
  )
  select jsonb_build_object(
    'ok', true,
    'work_date', v_date,
    'total_count', counted.total_count,
    'offset', v_offset,
    'limit', v_limit,
    'rows', rows_json.rows,
    'summary_rows', summary_json.summary_rows,
    'destinations', dest_json.destinations
  )
  into v_result
  from counted, rows_json, summary_json, dest_json;

  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_qr_quality_evaluations_v1102(p_qr_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype; v_qr_key text:=btrim(coalesce(p_qr_key,'')); v_result jsonb;
begin
  select * into v_profile from public.seika_quality_profile_v1102();
  if not found then raise exception '品質評価を閲覧する権限がありません' using errcode='42501'; end if;
  if v_qr_key='' or char_length(v_qr_key)>160 then raise exception 'QRキーが不正です'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'qr_key',e.qr_key,'lot_id',e.lot_id,'lot_no',e.lot_no,'item_name',e.item_name,
    'grade',e.grade,'issues',e.issues,'memo',e.memo,'correction_reason',e.correction_reason,
    'evaluated_at',e.evaluated_at,'evaluated_by_name',e.evaluated_by_name,'supersedes_id',e.supersedes_id,
    'is_superseded',exists(select 1 from public.qr_quality_evaluations newer where newer.supersedes_id=e.id and newer.active),
    'can_add_photos',e.evaluated_by=auth.uid() and e.grade<>'good' and (select count(*) from public.qr_quality_photos cp where cp.evaluation_id=e.id and cp.upload_status='finalized' and cp.active)<3,
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',ph.id,'storage_path',ph.storage_path,'content_type',ph.content_type,'byte_size',ph.declared_byte_size,'created_at',ph.created_at) order by ph.created_at) from public.qr_quality_photos ph where ph.evaluation_id=e.id and ph.upload_status='finalized' and ph.active),'[]'::jsonb)
  ) order by e.evaluated_at desc,e.created_at desc),'[]'::jsonb) into v_result
  from public.qr_quality_evaluations e where e.qr_key=v_qr_key and e.active;
  return jsonb_build_object('ok',true,'evaluations',v_result);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_qr_quality_evaluations_v1103(p_target_month date DEFAULT NULL::date, p_grade text DEFAULT NULL::text, p_item_query text DEFAULT NULL::text, p_buyer_legacy_user_id text DEFAULT NULL::text, p_unacknowledged_only boolean DEFAULT false, p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date;
  v_grade text := nullif(lower(btrim(coalesce(p_grade, ''))), '');
  v_query text := nullif(btrim(coalesce(p_item_query, '')), '');
  v_buyer text := nullif(btrim(coalesce(p_buyer_legacy_user_id, '')), '');
  v_limit integer := greatest(1, least(coalesce(p_limit, 500), 1000));
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 100000));
  v_rows jsonb;
  v_total bigint;
begin
  select * into v_profile from public.seika_quality_profile_v1102();
  if not found then raise exception '品質評価を閲覧する権限がありません' using errcode = '42501'; end if;
  if v_grade is not null and v_grade not in ('good', 'review', 'bad') then raise exception '判定は good / review / bad のいずれかです' using errcode = '22023'; end if;
  if char_length(coalesce(v_query, '')) > 100 or char_length(coalesce(v_buyer, '')) > 100 then raise exception '検索条件が不正です' using errcode = '22023'; end if;
  v_month := case when p_target_month is null then null else date_trunc('month', p_target_month)::date end;

  with latest as (
    select e.*, q.lot_id as current_lot_id, q.item_id::text as current_item_id,
      coalesce(q.item_name, e.item_name) as current_item_name, ctx as buyer_context
    from public.qr_quality_evaluations e
    left join lateral public.seika_v1144_resolve_quality_lot(e.lot_id::text, e.qr_key) q on true
    cross join lateral public.seika_quality_buyer_context_for_item_v1144(q.lot_id, coalesce(q.item_name, e.item_name)) ctx
    where e.active = true and e.invalidated_at is null and e.invalidated_by_lot_delete = false
      and not exists (select 1 from public.qr_quality_evaluations n where n.supersedes_id = e.id and n.active = true and n.invalidated_at is null and n.invalidated_by_lot_delete = false)
      and (v_month is null or (e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo') and e.evaluated_at < ((v_month + interval '1 month')::timestamp at time zone 'Asia/Tokyo')))
      and (v_grade is null or e.grade = v_grade)
      and (v_query is null or coalesce(q.item_name, e.item_name, '') ilike '%' || v_query || '%')
      and (not p_unacknowledged_only or (e.grade in ('review', 'bad') and e.acknowledged_at is null))
      and (v_buyer is null or exists (select 1 from jsonb_array_elements(ctx -> 'buyers') b where b ->> 'legacy_user_id' = v_buyer))
  ), numbered as (
    select l.*, count(*) over () total_count from latest l
  ), paged as (
    select * from numbered
    order by case grade when 'bad' then 1 when 'review' then 2 else 3 end, evaluated_at desc, created_at desc, id desc
    limit v_limit offset v_offset
  )
  select coalesce(max(total_count), 0), coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'qr_key', p.qr_key, 'lot_id', p.lot_id, 'lot_no', p.lot_no,
    'item_id', p.current_item_id, 'item_name', p.current_item_name, 'evaluated_item_name', p.item_name,
    'grade', p.grade, 'issues', p.issues, 'memo', p.memo, 'correction_reason', p.correction_reason,
    'evaluated_at', p.evaluated_at, 'evaluated_by', p.evaluated_by, 'evaluated_by_name', p.evaluated_by_name,
    'supersedes_id', p.supersedes_id, 'is_superseded', false,
    'acknowledged_at', p.acknowledged_at, 'acknowledged_by', p.acknowledged_by, 'acknowledged_by_name', p.acknowledged_by_name,
    'buyers', p.buyer_context -> 'buyers', 'buyer_source', p.buyer_context ->> 'buyer_source',
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path, 'original_name', ph.original_name, 'content_type', ph.content_type, 'byte_size', ph.declared_byte_size, 'created_at', ph.created_at, 'finalized_at', ph.finalized_at) order by ph.created_at) from public.qr_quality_photos ph where ph.evaluation_id = p.id and ph.upload_status = 'finalized'), '[]'::jsonb)
  ) order by case p.grade when 'bad' then 1 when 'review' then 2 else 3 end, p.evaluated_at desc, p.created_at desc, p.id desc), '[]'::jsonb)
  into v_total, v_rows from paged p;
  return jsonb_build_object('ok', true, 'evaluations', v_rows, 'total_count', v_total, 'limit', v_limit, 'offset', v_offset);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_qr_quality_evaluations_v1158(p_target_month date DEFAULT NULL::date, p_grade text DEFAULT NULL::text, p_item_query text DEFAULT NULL::text, p_buyer_legacy_user_id text DEFAULT NULL::text, p_unacknowledged_only boolean DEFAULT false, p_sort_order text DEFAULT 'grade'::text, p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date;
  v_grade text := nullif(lower(btrim(coalesce(p_grade,''))), '');
  v_item_query text := nullif(btrim(coalesce(p_item_query,'')), '');
  v_buyer_legacy_user_id text := nullif(btrim(coalesce(p_buyer_legacy_user_id,'')), '');
  v_sort_order text := lower(btrim(coalesce(p_sort_order, 'grade')));
  v_limit integer := greatest(1, least(coalesce(p_limit,500), 1000));
  v_offset integer := greatest(0, least(coalesce(p_offset,0), 100000));
  v_rows jsonb;
  v_total bigint;
begin
  select * into v_profile from public.seika_quality_profile_v1102();
  if not found then
    raise exception '品質評価を閲覧する権限がありません' using errcode = '42501';
  end if;
  if v_grade is not null and v_grade not in ('good','review','bad') then
    raise exception '判定は good / review / bad のいずれかです' using errcode = '22023';
  end if;
  if v_sort_order not in ('grade','received_newest','received_oldest') then
    raise exception '表示順が不正です' using errcode = '22023';
  end if;
  if char_length(coalesce(v_item_query,'')) > 100 then
    raise exception '品目検索は100文字以内です' using errcode = '22023';
  end if;
  if char_length(coalesce(v_buyer_legacy_user_id,'')) > 100 then
    raise exception '仕入れ担当者IDが不正です' using errcode = '22023';
  end if;
  v_month := case when p_target_month is null then null else date_trunc('month',p_target_month)::date end;

  with latest as (
    select
      e.id, e.qr_key, e.lot_id, e.lot_no, e.item_name, e.grade, e.issues, e.memo,
      e.correction_reason, e.evaluated_at, e.evaluated_by, e.evaluated_by_name,
      e.supersedes_id, e.created_at, e.acknowledged_at, e.acknowledged_by,
      e.acknowledged_by_name, q.item_id::text as item_id,
      coalesce(q.item_name,e.item_name) as current_item_name,
      q.received_date::date as received_date
    from public.qr_quality_evaluations e
    join public.qr_lots q on q.qr_key = e.qr_key and coalesce(q.active, true) = true
    where coalesce(e.active, true) = true
      and not exists (
        select 1
        from public.qr_quality_evaluations newer
        where newer.supersedes_id = e.id and coalesce(newer.active, true) = true
      )
      and (v_month is null or (
        e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
        and e.evaluated_at < ((v_month + interval '1 month')::timestamp at time zone 'Asia/Tokyo')
      ))
      and (v_grade is null or e.grade = v_grade)
      and (v_item_query is null or coalesce(q.item_name,e.item_name,'') ilike '%' || v_item_query || '%')
      and (not p_unacknowledged_only or e.acknowledged_at is null)
      and (v_buyer_legacy_user_id is null or exists (
        select 1
        from public.seika_quality_buyers_for_item_v1103(q.item_id::text) b
        where b.legacy_user_id = v_buyer_legacy_user_id
      ))
  ), numbered as (
    select l.*, count(*) over () as total_count
    from latest l
  ), paged as (
    select *
    from numbered
    order by
      case when v_sort_order = 'grade' then case grade when 'bad' then 1 when 'review' then 2 else 3 end end asc nulls last,
      case when v_sort_order = 'received_newest' then received_date end desc nulls last,
      case when v_sort_order = 'received_oldest' then received_date end asc nulls last,
      evaluated_at desc, created_at desc, id desc
    limit v_limit offset v_offset
  )
  select coalesce(max(total_count),0),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'qr_key', p.qr_key,
           'lot_id', p.lot_id,
           'lot_no', p.lot_no,
           'item_id', p.item_id,
           'item_name', p.current_item_name,
           'evaluated_item_name', p.item_name,
           'grade', p.grade,
           'issues', p.issues,
           'memo', p.memo,
           'correction_reason', p.correction_reason,
           'evaluated_at', p.evaluated_at,
           'received_date', p.received_date,
           'evaluated_by', p.evaluated_by,
           'evaluated_by_name', p.evaluated_by_name,
           'supersedes_id', p.supersedes_id,
           'is_superseded', false,
           'acknowledged_at', p.acknowledged_at,
           'acknowledged_by', p.acknowledged_by,
           'acknowledged_by_name', p.acknowledged_by_name,
           'buyers', coalesce((
             select jsonb_agg(jsonb_build_object(
               'legacy_user_id', b.legacy_user_id,
               'display_name', b.display_name
             ) order by b.legacy_user_id)
             from public.seika_quality_buyers_for_item_v1103(p.item_id) b
           ), '[]'::jsonb),
           'photos', coalesce((
             select jsonb_agg(jsonb_build_object(
               'id', ph.id,
               'storage_path', ph.storage_path,
               'original_name', ph.original_name,
               'content_type', ph.content_type,
               'byte_size', ph.declared_byte_size,
               'created_at', ph.created_at,
               'finalized_at', ph.finalized_at
             ) order by ph.created_at)
             from public.qr_quality_photos ph
             where ph.evaluation_id = p.id
               and ph.upload_status = 'finalized'
               and coalesce(ph.active, true) = true
           ), '[]'::jsonb)
         ) order by
           case when v_sort_order = 'grade' then case p.grade when 'bad' then 1 when 'review' then 2 else 3 end end asc nulls last,
           case when v_sort_order = 'received_newest' then p.received_date end desc nulls last,
           case when v_sort_order = 'received_oldest' then p.received_date end asc nulls last,
           p.evaluated_at desc, p.created_at desc, p.id desc), '[]'::jsonb)
    into v_total, v_rows
  from paged p;

  return jsonb_build_object(
    'ok', true,
    'evaluations', v_rows,
    'total_count', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'sort_order', v_sort_order
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_qr_quality_evaluations_v1159(p_target_month date DEFAULT NULL::date, p_grade text DEFAULT NULL::text, p_item_query text DEFAULT NULL::text, p_buyer_legacy_user_id text DEFAULT NULL::text, p_unacknowledged_only boolean DEFAULT false, p_sort_order text DEFAULT 'grade'::text, p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date;
  v_grade text:=nullif(lower(btrim(coalesce(p_grade,''))),'');
  v_query text:=nullif(btrim(coalesce(p_item_query,'')),'');
  v_buyer text:=nullif(btrim(coalesce(p_buyer_legacy_user_id,'')),'');
  v_sort text:=lower(btrim(coalesce(p_sort_order,'grade')));
  v_limit integer:=greatest(1,least(coalesce(p_limit,500),1000));
  v_offset integer:=greatest(0,least(coalesce(p_offset,0),100000));
  v_rows jsonb;
  v_total bigint;
begin
  select p.* into v_profile from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if not found then raise exception '品質評価を閲覧する権限がありません' using errcode='42501'; end if;
  if v_grade is not null and v_grade not in ('good','review','bad') then raise exception '判定が不正です' using errcode='22023'; end if;
  if v_sort not in ('grade','received_newest','received_oldest') then raise exception '表示順が不正です' using errcode='22023'; end if;
  if char_length(coalesce(v_query,''))>100 or char_length(coalesce(v_buyer,''))>100 then raise exception '検索条件が不正です' using errcode='22023'; end if;
  v_month:=case when p_target_month is null then null else date_trunc('month',p_target_month)::date end;

  with latest as (
    select e.id,e.qr_key,e.lot_id,e.lot_no,e.item_name,e.grade,e.issues,e.memo,e.correction_reason,e.evaluated_at,e.evaluated_by,e.evaluated_by_name,e.supersedes_id,e.created_at,e.acknowledged_at,e.acknowledged_by,e.acknowledged_by_name,
      q.id as current_lot_id,q.item_id::text as item_id,coalesce(q.item_name,e.item_name) as current_item_name,q.received_date::date as received_date,
      public.seika_quality_buyer_context_for_lot_v1159(q.id) as buyer_context
    from public.qr_quality_evaluations e
    join lateral (
      select lot.* from public.qr_lots lot
      where (e.lot_id is not null and lot.id::text=e.lot_id::text) or lot.qr_key=e.qr_key
      order by case when e.lot_id is not null and lot.id::text=e.lot_id::text then 0 else 1 end,coalesce(lot.active,true) desc,lot.created_at desc,lot.id desc
      limit 1
    ) q on true
    where coalesce(e.active,true)=true
      and (to_jsonb(e)->>'invalidated_at' is null)
      and coalesce((to_jsonb(e)->>'invalidated_by_lot_delete')::boolean,false)=false
      and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and coalesce(n.active,true)=true and to_jsonb(n)->>'invalidated_at' is null and coalesce((to_jsonb(n)->>'invalidated_by_lot_delete')::boolean,false)=false)
      and (v_month is null or (e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo') and e.evaluated_at < ((v_month+interval '1 month')::timestamp at time zone 'Asia/Tokyo')))
      and (v_grade is null or e.grade=v_grade)
      and (v_query is null or coalesce(q.item_name,e.item_name,'') ilike '%'||v_query||'%')
      and (not p_unacknowledged_only or (e.grade in ('review','bad') and e.acknowledged_at is null))
  ), filtered as (
    select * from latest l
    where v_buyer is null or exists(select 1 from jsonb_array_elements(l.buyer_context->'buyers') b where b->>'legacy_user_id'=v_buyer)
  ), numbered as (
    select f.*,count(*) over() total_count from filtered f
  ), paged as (
    select * from numbered
    order by
      case when v_sort='grade' then case grade when 'bad' then 1 when 'review' then 2 else 3 end end asc nulls last,
      case when v_sort='received_newest' then received_date end desc nulls last,
      case when v_sort='received_oldest' then received_date end asc nulls last,
      evaluated_at desc,created_at desc,id desc
    limit v_limit offset v_offset
  )
  select coalesce(max(total_count),0),coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'qr_key',p.qr_key,'lot_id',p.lot_id,'lot_no',p.lot_no,'item_id',p.item_id,'item_name',p.current_item_name,'evaluated_item_name',p.item_name,
    'grade',p.grade,'issues',p.issues,'memo',p.memo,'correction_reason',p.correction_reason,'evaluated_at',p.evaluated_at,'received_date',p.received_date,
    'evaluated_by',p.evaluated_by,'evaluated_by_name',p.evaluated_by_name,'supersedes_id',p.supersedes_id,'is_superseded',false,
    'acknowledged_at',p.acknowledged_at,'acknowledged_by',p.acknowledged_by,'acknowledged_by_name',p.acknowledged_by_name,
    'buyers',coalesce(p.buyer_context->'buyers','[]'::jsonb),'buyer_source',p.buyer_context->>'buyer_source',
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',ph.id,'storage_path',ph.storage_path,'original_name',ph.original_name,'content_type',ph.content_type,'byte_size',ph.declared_byte_size,'created_at',ph.created_at,'finalized_at',ph.finalized_at) order by ph.created_at) from public.qr_quality_photos ph where ph.evaluation_id=p.id and ph.upload_status='finalized' and coalesce(ph.active,true)=true),'[]'::jsonb)
  ) order by
    case when v_sort='grade' then case p.grade when 'bad' then 1 when 'review' then 2 else 3 end end asc nulls last,
    case when v_sort='received_newest' then p.received_date end desc nulls last,
    case when v_sort='received_oldest' then p.received_date end asc nulls last,
    p.evaluated_at desc,p.created_at desc,p.id desc),'[]'::jsonb)
  into v_total,v_rows from paged p;

  return jsonb_build_object('ok',true,'evaluations',v_rows,'total_count',v_total,'limit',v_limit,'offset',v_offset,'sort_order',v_sort);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_unified_waste_records_v1144(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_from date:=least(coalesce(p_from,(now() at time zone 'Asia/Tokyo')::date),coalesce(p_to,(now() at time zone 'Asia/Tokyo')::date));
  v_to date:=greatest(coalesce(p_from,(now() at time zone 'Asia/Tokyo')::date),coalesce(p_to,(now() at time zone 'Asia/Tokyo')::date));
  v_rows jsonb;
begin
  v_profile:=public.seika_v1144_require_active_profile();
  with qr_base as (
    select q.*,l.pack_weight,pw.pack_weight_numeric,
      case when q.weight is not null and q.weight>0 then q.weight
           when q.before_weight is not null and q.after_weight is not null and abs(q.before_weight-q.after_weight)>0 then abs(q.before_weight-q.after_weight)
           when pw.pack_weight_numeric is not null and pw.pack_weight_numeric>0 and q.qty>0 then round(pw.pack_weight_numeric*q.qty,3)
           else null end resolved_weight,
      case when q.weight is not null and q.weight>0 then '確定'
           when q.before_weight is not null and q.after_weight is not null and abs(q.before_weight-q.after_weight)>0 then '重量差分換算'
           when pw.pack_weight_numeric is not null and pw.pack_weight_numeric>0 and q.qty>0 then '量目換算'
           else '未確定' end resolved_weight_status
    from public.qr_lot_movements q
    left join public.qr_lots l on l.id=q.lot_id
    cross join lateral (
      select public.seika_parse_kg_v1162(l.pack_weight) as pack_weight_numeric
    ) pw
    where q.movement_type='廃棄'
      and (coalesce(q.occurred_at,q.created_at) at time zone 'Asia/Tokyo')::date between v_from and v_to
      and q.cancelled_at is null and q.reversed_operation_id is null
      and not public.seika_v1144_qr_operation_cancelled(q.operation_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'source','qr','source_id',q.id::text,'operation_id',q.operation_id,'occurred_at',coalesce(q.occurred_at,q.created_at),
      'date',(coalesce(q.occurred_at,q.created_at) at time zone 'Asia/Tokyo')::date,
      'item_name',q.item_name,'item_id',q.item_id,'lot_no',q.lot_no,'qr_key',q.qr_key,'origin',q.origin,'supplier',q.supplier,'cooperative_name',q.cooperative_name,
      'qty',q.qty,'unit',q.unit,'weight',q.resolved_weight,'weight_status',q.resolved_weight_status,
      'reason',q.reason,'memo',q.memo,'user_name',q.user_name,
      'purchase_price_yen_per_kg',q.purchase_price_yen_per_kg,'waste_amount_yen',q.waste_amount_yen,
      'price_match_type',coalesce(q.price_match_type,'未計算'),'price_match_reason',coalesce(q.price_match_reason,case when q.resolved_weight is null then '廃棄重量が確定していないため金額未計算' else '' end),
      'price_source_supplier',q.price_source_supplier,'price_average_count',coalesce(q.price_average_count,0),'price_reference_date',q.price_reference_date,'price_calculated_at',q.price_calculated_at
    ) order by coalesce(q.occurred_at,q.created_at) desc),'[]'::jsonb) into v_rows
  from qr_base q;
  return jsonb_build_object('ok',true,'from',v_from,'to',v_to,'rows',v_rows);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.mark_monthly_archive_created_v1101(p_module text, p_target_month date, p_file_name text, p_row_count bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date := date_trunc('month',p_target_month)::date;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or not public.seika_archive_module_allowed_v1101(p_module,v_profile.role) then
    raise exception 'Excelä½æãè¨é²ããæ¨©éãããã¾ãã' using errcode='42501';
  end if;
  if v_month >= date_trunc('month',current_date)::date then
    raise exception 'ä¿å­ç®¡çã®å¯¾è±¡ã¯åæä»¥åã§ã';
  end if;

  insert into public.seika_monthly_archives(
    module,target_month,status,file_name,row_count,
    excel_created_at,excel_created_by,excel_created_by_name,updated_at
  ) values (
    p_module,v_month,'excel_created',left(coalesce(p_file_name,''),240),greatest(coalesce(p_row_count,0),0),
    now(),v_profile.id,v_profile.display_name,now()
  )
  on conflict(module,target_month) do update set
    status=case when public.seika_monthly_archives.status='deleted' then 'deleted' else 'excel_created' end,
    file_name=excluded.file_name,
    row_count=excluded.row_count,
    excel_created_at=excluded.excel_created_at,
    excel_created_by=excluded.excel_created_by,
    excel_created_by_name=excluded.excel_created_by_name,
    excel_saved_at=case when public.seika_monthly_archives.status='deleted' then public.seika_monthly_archives.excel_saved_at else null end,
    excel_saved_by=case when public.seika_monthly_archives.status='deleted' then public.seika_monthly_archives.excel_saved_by else null end,
    excel_saved_by_name=case when public.seika_monthly_archives.status='deleted' then public.seika_monthly_archives.excel_saved_by_name else null end,
    updated_at=now();

  return jsonb_build_object('ok',true,'status','excel_created');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.mark_monthly_quality_archive_created_v1102(p_target_month date, p_file_name text, p_row_count bigint, p_photo_count bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_month date:=date_trunc('month',p_target_month)::date;v_next date:=(date_trunc('month',p_target_month)+interval '1 month')::date;v_rows bigint;v_photos bigint;v_pending bigint;v_file text:=left(btrim(coalesce(p_file_name,'')),240);
begin
  select * into v_profile from public.seika_archive_profile_v1101();if not found or not public.seika_archive_module_allowed_v1101('quality',v_profile.role)then raise exception '品質評価Excel作成を記録する権限がありません' using errcode='42501';end if;if v_month>=date_trunc('month',now() at time zone 'Asia/Tokyo')::date then raise exception '保存管理の対象は前月以前です';end if;if v_file='' then raise exception 'Excelファイル名が必要です';end if;
  perform pg_advisory_xact_lock(hashtextextended('quality:'||v_month::text,1102));select count(distinct e.id),count(p.id)filter(where p.upload_status='finalized'),count(p.id)filter(where p.upload_status='pending')into v_rows,v_photos,v_pending from public.qr_quality_evaluations e join public.qr_lots q on q.qr_key=e.qr_key and q.active=true left join public.qr_quality_photos p on p.evaluation_id=e.id and p.active=true where e.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo');if v_pending<>0 then raise exception '未確定の品質写真があります。写真を確定またはStorage APIで取り消してください';end if;if coalesce(p_row_count,-1)<>v_rows or coalesce(p_photo_count,-1)<>v_photos then raise exception '品質評価または写真の件数が一致しません。Excelを作り直してください';end if;
  insert into public.seika_monthly_archives(module,target_month,status,file_name,row_count,photo_count,excel_created_at,excel_created_by,excel_created_by_name,updated_at)values('quality',v_month,'excel_created',v_file,v_rows,v_photos,now(),v_profile.id,v_profile.display_name,now())on conflict(module,target_month)do update set status='excel_created',file_name=excluded.file_name,row_count=excluded.row_count,photo_count=excluded.photo_count,excel_created_at=excluded.excel_created_at,excel_created_by=excluded.excel_created_by,excel_created_by_name=excluded.excel_created_by_name,excel_saved_at=null,excel_saved_by=null,excel_saved_by_name=null,updated_at=now()where public.seika_monthly_archives.status not in ('deleting','deleted');if not found then raise exception '整理中または整理済みの月はExcel作成記録を変更できません';end if;return jsonb_build_object('ok',true,'status','excel_created','row_count',v_rows,'photo_count',v_photos);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.prepare_monthly_quality_purge_v1102(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_month date:=date_trunc('month',p_target_month)::date;v_next date:=(date_trunc('month',p_target_month)+interval '1 month')::date;v_paths jsonb;
begin
  select * into v_profile from public.seika_archive_profile_v1101();if not found or v_profile.role<>'admin' then raise exception '管理者権限が必要です' using errcode='42501';end if;if v_month>=(date_trunc('month',now() at time zone 'Asia/Tokyo')-interval '3 months')::date then raise exception '3か月分の保持期間が終わっていません';end if;perform pg_advisory_xact_lock(hashtextextended('quality:'||v_month::text,1102));if not exists(select 1 from public.seika_monthly_archives where module='quality'and target_month=v_month and status in ('excel_saved','deleting')and excel_saved_at is not null)then raise exception 'Excel保存確認済みの月だけ削除できます';end if;
  if exists(select 1 from public.qr_quality_evaluations child join public.qr_quality_evaluations parent on parent.id=child.supersedes_id join public.qr_lots parent_lot on parent_lot.qr_key=parent.qr_key and parent_lot.active=true where parent.active=true and child.active=true and parent.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and parent.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo')and not(child.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and child.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo')))then raise exception '後月に残る訂正評価が参照しているため、この月は削除できません';end if;
  select coalesce(jsonb_agg(p.storage_path order by p.storage_path),'[]'::jsonb)into v_paths from public.qr_quality_photos p join public.qr_quality_evaluations e on e.id=p.evaluation_id and e.active=true join public.qr_lots q on q.qr_key=e.qr_key and q.active=true where p.active=true and e.evaluated_at>=(v_month::timestamp at time zone 'Asia/Tokyo')and e.evaluated_at<(v_next::timestamp at time zone 'Asia/Tokyo');update public.seika_monthly_archives set status='deleting',updated_at=now()where module='quality'and target_month=v_month;return jsonb_build_object('ok',true,'status','deleting','bucket','qr-quality-photos','storage_paths',v_paths);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.prepare_monthly_quality_purge_v1166(p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date := date_trunc('month', p_target_month)::date;
  v_next date := (date_trunc('month', p_target_month) + interval '1 month')::date;
  v_paths jsonb;
  v_rows bigint := 0;
  v_photos bigint := 0;
  v_archive public.seika_monthly_archives%rowtype;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or v_profile.role <> 'admin' then
    raise exception '管理者権限が必要です' using errcode = '42501';
  end if;
  if p_target_month is null then
    raise exception '対象月が不正です' using errcode = '22023';
  end if;
  if v_month >= (date_trunc('month', now() at time zone 'Asia/Tokyo') - interval '3 months')::date then
    raise exception '品質評価は直近3か月を保持します。保持期間が終わっていません' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('quality:' || v_month::text, 1102));
  select * into v_archive
  from public.seika_monthly_archives
  where module = 'quality' and target_month = v_month
  for update;

  if not found then
    raise exception 'Excel保存確認済みの月だけ削除できます' using errcode = '22023';
  end if;
  if v_archive.status = 'deleted' then
    return jsonb_build_object(
      'ok', true, 'already_deleted', true, 'status', 'deleted',
      'bucket', 'qr-quality-photos', 'storage_paths', '[]'::jsonb,
      'cleanup_row_count', coalesce(v_archive.deleted_count, 0),
      'cleanup_photo_count', coalesce(v_archive.deleted_photo_count, 0)
    );
  end if;
  if v_archive.status not in ('excel_saved', 'deleting') or v_archive.excel_saved_at is null then
    raise exception 'Excel保存確認済みの月だけ削除できます' using errcode = '22023';
  end if;

  -- 当月の親評価を後月の評価が参照している場合、訂正履歴を壊さないため停止します。
  if exists (
    select 1
    from public.qr_quality_evaluations parent
    join public.qr_quality_evaluations child on child.supersedes_id = parent.id
    where parent.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
      and parent.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo')
      and not (
        child.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
        and child.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo')
      )
  ) then
    raise exception '後月に残る訂正評価が参照しているため、この月は削除できません' using errcode = '22023';
  end if;

  select count(*) into v_rows
  from public.qr_quality_evaluations e
  where e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
    and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo');

  select count(*) into v_photos
  from public.qr_quality_photos p
  join public.qr_quality_evaluations e on e.id = p.evaluation_id
  where e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
    and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo');

  select coalesce(jsonb_agg(distinct p.storage_path order by p.storage_path), '[]'::jsonb)
  into v_paths
  from public.qr_quality_photos p
  join public.qr_quality_evaluations e on e.id = p.evaluation_id
  where e.evaluated_at >= (v_month::timestamp at time zone 'Asia/Tokyo')
    and e.evaluated_at < (v_next::timestamp at time zone 'Asia/Tokyo')
    and nullif(btrim(p.storage_path), '') is not null;

  update public.seika_monthly_archives
  set status = 'deleting', updated_at = now()
  where module = 'quality' and target_month = v_month;

  return jsonb_build_object(
    'ok', true, 'already_deleted', false, 'status', 'deleting',
    'bucket', 'qr-quality-photos', 'storage_paths', v_paths,
    'cleanup_row_count', v_rows, 'cleanup_photo_count', v_photos
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.purge_monthly_archive_v1101(p_module text, p_target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_month date := date_trunc('month',p_target_month)::date;
  v_next date := (date_trunc('month',p_target_month)+interval '1 month')::date;
  v_count bigint := 0;
  v_lot record;
  v_move record;
  v_base record;
  v_qty numeric;
  v_location text;
  v_deleted boolean;
  v_price_count bigint := 0;
  v_type text;
  v_amount numeric;
  v_before numeric;
  v_after numeric;
  v_move_json jsonb;
  v_lot_json jsonb;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or v_profile.role <> 'admin' then
    raise exception '管理者権限が必要です' using errcode='42501';
  end if;
  if v_month >= (date_trunc('month',current_date)-interval '3 months')::date then
    raise exception '3か月分の保持期間が終わっていません';
  end if;
  if not exists(
    select 1 from public.seika_monthly_archives
    where module=p_module and target_month=v_month
      and status='excel_saved' and excel_saved_at is not null
  ) then
    raise exception 'Excel保存確認済みの月だけ削除できます';
  end if;

  if p_module='waste' then
    perform set_config('seika.monthly_archive_purge','on',true);
    delete from public.waste_records
    where waste_date>=v_month and waste_date<v_next;
    get diagnostics v_count=row_count;
  elsif p_module='qr' then
    for v_lot in select * from public.qr_lots loop
      v_lot_json:=to_jsonb(v_lot);
      if coalesce(nullif(v_lot_json->>'received_date','')::date,(coalesce(v_lot.created_at,now()) at time zone 'Asia/Tokyo')::date)>=v_next then
        continue;
      end if;
      select s.quantity,s.storage_location,s.deleted
      into v_base
      from public.qr_lot_monthly_snapshots s
      where s.lot_id=v_lot.id::text and s.target_month<v_month
      order by s.target_month desc limit 1;

      if found then
        v_qty:=coalesce(v_base.quantity,0);
        v_location:=coalesce(v_base.storage_location,'');
        v_deleted:=coalesce(v_base.deleted,false);
      else
        v_qty:=coalesce((v_lot_json->>'received_qty')::numeric,(v_lot_json->>'initial_quantity')::numeric,0);
        v_location:=coalesce(v_lot_json->>'storage_location','');
        v_deleted:=false;
      end if;

      for v_move in
        select q.* from public.qr_lot_movements q
        where (q.lot_id::text=v_lot.id::text or q.qr_key=coalesce(v_lot_json->>'qr_key',''))
          and (coalesce((to_jsonb(q)->>'occurred_at')::timestamptz,q.created_at) at time zone 'Asia/Tokyo')<v_next
          and (coalesce((to_jsonb(q)->>'occurred_at')::timestamptz,q.created_at) at time zone 'Asia/Tokyo')>=
            coalesce((select (s.target_month+interval '1 month')::timestamp
                      from public.qr_lot_monthly_snapshots s
                      where s.lot_id=v_lot.id::text and s.target_month<v_month
                      order by s.target_month desc limit 1),'-infinity'::timestamp)
        order by coalesce((to_jsonb(q)->>'occurred_at')::timestamptz,q.created_at),q.created_at
      loop
        v_move_json:=to_jsonb(v_move);
        v_type:=coalesce(v_move_json->>'movement_type','');
        v_location:=coalesce(nullif(v_move_json->>'storage_location',''),v_location);
        v_after:=nullif(v_move_json->>'after_quantity','')::numeric;
        v_before:=nullif(v_move_json->>'before_quantity','')::numeric;
        v_amount:=abs(coalesce(nullif(v_move_json->>'qty','')::numeric,nullif(v_move_json->>'quantity','')::numeric,0));
        if v_type like '%完全削除%' or v_type like '%ロット削除%' then
          v_qty:=0;v_deleted:=true;
        elsif v_after is not null then
          v_qty:=v_after;v_deleted:=false;
        elsif v_type like '%取消%' and v_before is not null then
          v_qty:=v_before;
        elsif v_type like '%廃棄%' or v_type like '%出庫%' or v_type like '%調整減%' then
          v_qty:=greatest(v_qty-v_amount,0);
        elsif v_type like '%入庫%' or v_type like '%調整増%' then
          if not ((v_before is null or v_before=0) and v_amount=coalesce((v_lot_json->>'received_qty')::numeric,(v_lot_json->>'initial_quantity')::numeric,0)) then
            v_qty:=v_qty+v_amount;
          end if;
        end if;
      end loop;

      insert into public.qr_lot_monthly_snapshots(
        target_month,lot_id,qr_key,lot_no,quantity,storage_location,deleted,calculated_at
      ) values(
        v_month,v_lot.id::text,v_lot_json->>'qr_key',v_lot_json->>'lot_no',greatest(coalesce(v_qty,0),0),v_location,v_deleted,now()
      ) on conflict(target_month,lot_id) do update set
        qr_key=excluded.qr_key,lot_no=excluded.lot_no,quantity=excluded.quantity,
        storage_location=excluded.storage_location,deleted=excluded.deleted,calculated_at=now();
    end loop;

    delete from public.qr_lot_movements q
    where (coalesce((to_jsonb(q)->>'occurred_at')::timestamptz,q.created_at) at time zone 'Asia/Tokyo')>=v_month
      and (coalesce((to_jsonb(q)->>'occurred_at')::timestamptz,q.created_at) at time zone 'Asia/Tokyo')<v_next;
    get diagnostics v_count=row_count;
  elsif p_module='trimming' then
    delete from public.trimming_jobs
    where work_date>=v_month and work_date<v_next;
    get diagnostics v_count=row_count;
    delete from public.purchase_prices
    where week_start>=v_month and week_start<v_next;
    get diagnostics v_price_count=row_count;
    v_count:=v_count+v_price_count;
  else
    raise exception '対象区分が不正です';
  end if;

  update public.seika_monthly_archives
  set status='deleted',deleted_at=now(),deleted_by=v_profile.id,
      deleted_by_name=v_profile.display_name,deleted_count=v_count,updated_at=now()
  where module=p_module and target_month=v_month;

  return jsonb_build_object('ok',true,'status','deleted','deleted_count',v_count);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.qr_inventory_entry_operation_id(p_operation_id uuid, p_qr_key text)
 RETURNS uuid
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select (
    substr(md5(p_operation_id::text || ':' || coalesce(p_qr_key, '')), 1, 8) || '-' ||
    substr(md5(p_operation_id::text || ':' || coalesce(p_qr_key, '')), 9, 4) || '-' ||
    substr(md5(p_operation_id::text || ':' || coalesce(p_qr_key, '')), 13, 4) || '-' ||
    substr(md5(p_operation_id::text || ':' || coalesce(p_qr_key, '')), 17, 4) || '-' ||
    substr(md5(p_operation_id::text || ':' || coalesce(p_qr_key, '')), 21, 12)
  )::uuid;
$function$
;
CREATE OR REPLACE FUNCTION public.qr_lot_daily_state_v1211(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_today     date := (now() at time zone 'Asia/Tokyo')::date;
  v_from      date;
  v_to        date;
  v_row       record;
  v_lot       jsonb;
  v_moves     jsonb[];
  v_ats       timestamptz[];
  v_snaps     jsonb;
  v_n         int;
  v_out       jsonb[] := '{}'::jsonb[];
  v_changes   jsonb[];
  v_received  date;
  v_recv_qty  numeric;
  v_month     date;
  v_month_end date;
  v_ym        text;
  v_day       date;
  v_day_end   timestamptz;
  v_day_from  date;
  v_day_to    date;
  v_start     timestamptz;
  v_qty       numeric;
  v_loc       text;
  v_del       boolean;
  v_skipped   boolean;
  v_idx       int;
  v_m         jsonb;
  v_s         jsonb;
  v_at        timestamptz;
  v_type      text;
  v_mloc      text;
  v_after     numeric;
  v_before    numeric;
  v_amount    numeric;
  v_same      boolean;
  v_found     boolean;
  v_prev_q    numeric;
  v_prev_l    text;
  v_prev_d    boolean;
  v_has_prev  boolean;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and active = true) then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  v_from := coalesce(p_from, v_today - 97);
  v_to   := least(coalesce(p_to, v_today), v_today);
  if v_from > v_to then
    return jsonb_build_object('ok', true, 'today', to_char(v_today,'YYYY-MM-DD'),
                              'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
                              'lots', '[]'::jsonb);
  end if;

  for v_row in
    with lots as (
      select to_jsonb(l) as j from public.qr_lots l
    ),
    lk as (
      select j,
             coalesce(j->>'id','')      as lid,
             nullif(j->>'qr_key','')    as qk,
             nullif(j->>'lot_no','')    as ln
      from lots
    ),
    mv as (
      select t.j,
             nullif(t.j->>'lot_id','') as k_lot,
             nullif(t.j->>'qr_key','') as k_qr,
             nullif(t.j->>'lot_no','') as k_no,
             coalesce((t.j->>'occurred_at')::timestamptz,
                      (t.j->>'created_at')::timestamptz,
                      (t.j->>'updated_at')::timestamptz,
                      'epoch'::timestamptz) as at
      from (select to_jsonb(m) as j from public.qr_lot_movements m) t
    ),
    pairs as (
      select lk.lid, mv.j, mv.at from lk join mv on mv.k_lot = lk.lid
      union all
      select lk.lid, mv.j, mv.at from lk join mv on mv.k_qr  = lk.qk
      union all
      select lk.lid, mv.j, mv.at from lk join mv on mv.k_no  = lk.ln
    ),
    uniq as (
      select distinct on (lid, coalesce(j->>'id', at::text)) lid, j, at
      from pairs
      order by lid, coalesce(j->>'id', at::text), at
    ),
    agg as (
      select lid, array_agg(j order by at) as moves, array_agg(at order by at) as ats
      from uniq group by lid
    ),
    sn as (
      select coalesce(s.j->>'lot_id','') as lid,
             jsonb_agg(jsonb_build_object(
               'ym',  substr(s.j->>'target_month',1,7),
               'q',   (s.j->>'quantity')::numeric,
               'loc', coalesce(s.j->>'storage_location',''),
               'del', ((s.j->>'deleted') = 'true'))
               order by substr(s.j->>'target_month',1,7) desc) as snaps
      from (select to_jsonb(x) as j from public.qr_lot_monthly_snapshots x) s
      group by 1
    )
    select lk.j, a.moves, a.ats, sn.snaps
    from lk
    left join agg a on a.lid = lk.lid
    left join sn    on sn.lid = lk.lid
    order by lk.j->>'qr_key'
  loop
    v_lot := v_row.j;

    if coalesce(substr(v_lot->>'received_date',1,10),'') ~ '^\d{4}-\d{2}-\d{2}$' then
      v_received := substr(v_lot->>'received_date',1,10)::date;
    else
      v_received := (coalesce((v_lot->>'created_at')::timestamptz,
                              (v_lot->>'updated_at')::timestamptz)
                     at time zone 'Asia/Tokyo')::date;
    end if;
    if v_received is null then continue; end if;

    v_day_from := greatest(v_from, v_received);
    v_day_to   := v_to;
    if v_day_from > v_day_to then continue; end if;

    v_recv_qty := coalesce((v_lot->>'received_qty')::numeric,
                           (v_lot->>'initial_quantity')::numeric, 0);
    v_moves := coalesce(v_row.moves, '{}'::jsonb[]);
    v_ats   := coalesce(v_row.ats,   '{}'::timestamptz[]);
    v_n     := coalesce(array_length(v_moves,1),0);
    v_snaps := coalesce(v_row.snaps, '[]'::jsonb);

    v_changes  := '{}'::jsonb[];
    v_has_prev := false;

    v_month := date_trunc('month', v_day_from)::date;
    while v_month <= v_day_to loop
      v_month_end := (v_month + interval '1 month - 1 day')::date;
      v_ym := to_char(v_month,'YYYY-MM');

      v_found := false;
      for v_s in select e from jsonb_array_elements(v_snaps) e loop
        if (v_s->>'ym') < v_ym then
          if v_s->>'q' is not null then
            v_found := true;
            v_qty     := (v_s->>'q')::numeric;
            v_loc     := coalesce(v_s->>'loc','');
            v_del     := coalesce((v_s->>'del')::boolean,false);
            v_skipped := true;
            v_start   := (((date_trunc('month', ((v_s->>'ym')||'-01')::date) + interval '1 month')::date)::text
                          ||' 00:00:00')::timestamp at time zone 'Asia/Tokyo';
          end if;
          exit;
        end if;
      end loop;

      if not v_found then
        v_qty     := v_recv_qty;
        v_loc     := btrim(coalesce(v_lot->>'storage_location',''));
        v_del     := false;
        v_skipped := false;
        v_start   := '-infinity'::timestamptz;
      end if;

      v_idx := 1;
      v_day := greatest(v_month, v_day_from);
      while v_day <= least(v_month_end, v_day_to) loop
        v_day_end := (v_day::text||' 23:59:59.999')::timestamp at time zone 'Asia/Tokyo';
        while v_idx <= v_n loop
          v_at := v_ats[v_idx];
          exit when v_at > v_day_end;
          if v_at >= v_start then
            v_m    := v_moves[v_idx];
            v_type := coalesce(v_m->>'movement_type','');
            v_mloc := btrim(coalesce(v_m->>'storage_location',''));
            if v_mloc <> '' then v_loc := v_mloc; end if;

            if position('削除' in v_type) > 0 then
              v_qty := 0; v_del := true;
            else
              v_after := (v_m->>'after_quantity')::numeric;
              if v_after is not null then
                v_qty := v_after; v_del := false;
              else
                v_amount := abs(coalesce((v_m->>'qty')::numeric,
                                         (v_m->>'quantity')::numeric, 0));
                if position('取消' in v_type) > 0 then
                  v_before := (v_m->>'before_quantity')::numeric;
                  if v_before is not null then v_qty := v_before; end if;
                elsif position('廃棄' in v_type) > 0
                   or position('出庫' in v_type) > 0
                   or position('調整減' in v_type) > 0 then
                  v_qty := v_qty - v_amount;
                elsif position('入庫' in v_type) > 0
                   or position('調整増' in v_type) > 0 then
                  v_before := (v_m->>'before_quantity')::numeric;
                  v_same := (not v_skipped)
                            and position('入庫' in v_type) > 0
                            and (v_before is null or v_before = 0)
                            and abs(v_amount - v_recv_qty) < 1e-9
                            and (v_at at time zone 'Asia/Tokyo')::date = v_received;
                  if v_same then
                    v_skipped := true;
                  else
                    v_qty := v_qty + v_amount;
                  end if;
                end if;
              end if;
            end if;
          end if;
          v_idx := v_idx + 1;
        end loop;

        if (not v_has_prev)
           or v_prev_q is distinct from greatest(round(v_qty,2),0)
           or v_prev_l is distinct from v_loc
           or v_prev_d is distinct from v_del then
          v_prev_q := greatest(round(v_qty,2),0);
          v_prev_l := v_loc;
          v_prev_d := v_del;
          v_has_prev := true;
          v_changes := array_append(v_changes,
                         jsonb_build_array(to_char(v_day,'YYYY-MM-DD'), v_prev_q, v_prev_l, v_prev_d));
        end if;

        v_day := v_day + 1;
      end loop;

      v_month := (v_month + interval '1 month')::date;
    end loop;

    if coalesce(array_length(v_changes,1),0) > 0 then
      v_out := array_append(v_out, jsonb_build_object(
                 'id',   v_lot->>'id',
                 'from', to_char(v_day_from,'YYYY-MM-DD'),
                 'ch',   to_jsonb(v_changes)));
    end if;
  end loop;

  return jsonb_build_object('ok', true,
                            'today', to_char(v_today,'YYYY-MM-DD'),
                            'from',  to_char(v_from,'YYYY-MM-DD'),
                            'to',    to_char(v_to,'YYYY-MM-DD'),
                            'lots',  to_jsonb(v_out));
end
$function$
;
CREATE OR REPLACE FUNCTION public.recalc_trimming_job_price_v1195(p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r        record;
  v        jsonb;
  v_price  numeric;
  v_cost   numeric := 0;
  v_all    boolean := true;
  v_types  text[]  := array[]::text[];
  v_input  numeric;
  v_work   date;
  v_type   text;
  v_reason text;
  v_src    text;
  v_week   date;
  v_cnt    integer;
begin
  select work_date, input_weight_kg into v_work, v_input
  from public.trimming_jobs where id = p_job_id;

  for r in
    select l.qr_key, btrim(coalesce(l.item_name,'')) as item_name,
           l.origin, l.supplier, l.used_weight_kg,
           coalesce(q.received_date, v_work) as ref_date
    from public.trimming_job_lots l
    left join public.qr_lots q on q.qr_key = l.qr_key
    where l.trimming_job_id = p_job_id
  loop
    v := public.resolve_trimming_purchase_price_v1117(
           r.item_name, r.origin, r.supplier, r.ref_date);
    v_price  := nullif(v->>'price_yen_per_kg','')::numeric;
    v_type   := coalesce(v->>'match_type','未計算');
    v_reason := coalesce(v->>'match_reason','');
    v_src    := coalesce(v->>'source_supplier','');
    v_week   := nullif(v->>'source_week_start','')::date;
    v_cnt    := coalesce(nullif(v->>'average_count','')::integer,0);

    -- 最終フォールバック：入荷日の週以前に価格が無い場合は最古の登録価格を使う
    if coalesce(v_price,0) <= 0 then
      with latest as (
        select distinct on (pp.price_type, pp.origin,
                            public.trimming_normalize_supplier_v1117(pp.supplier))
               pp.price_yen_per_kg, pp.week_start
        from public.purchase_prices pp
        where btrim(pp.item_name) = any(public.seika_item_name_group_v1200(r.item_name))
        order by pp.price_type, pp.origin,
                 public.trimming_normalize_supplier_v1117(pp.supplier),
                 pp.week_start asc, pp.updated_at desc
      )
      select round(avg(price_yen_per_kg),0), count(*), min(week_start)
        into v_price, v_cnt, v_week
      from latest;

      if coalesce(v_price,0) > 0 then
        v_type   := '同一品目平均（登録前の入荷）';
        v_reason := concat('入荷日', r.ref_date::text,
                           'の週以前に登録価格が無いため、最も古い登録価格',
                           v_cnt, '件を平均して四捨五入');
        v_src    := '同一品目平均';
      else
        v_price := null;
      end if;
    end if;

    if coalesce(v_price,0) > 0 then
      v_cost := v_cost + coalesce(r.used_weight_kg,0) * v_price;
    else
      v_all   := false;
      v_price := null;
    end if;

    update public.trimming_job_lots
       set purchase_price_yen_per_kg = v_price,
           purchase_price_week_start = v_week,
           price_match_type          = v_type,
           price_match_reason        = v_reason,
           price_source_supplier     = v_src,
           price_average_count       = v_cnt
     where trimming_job_id = p_job_id and qr_key = r.qr_key;

    v_types := v_types || v_type;
  end loop;

  update public.trimming_jobs
     set purchase_price_yen_per_kg =
           case when v_all and coalesce(v_input,0) > 0 then round(v_cost / v_input, 2) end,
         input_cost_yen =
           case when v_all then round(v_cost, 0) end,
         price_match_summary =
           (select string_agg(distinct t, ' / ') from unnest(v_types) t),
         updated_at = pg_catalog.now()
   where id = p_job_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.recalculate_qr_waste_price_v1162(p_movement_id uuid, p_manual_unit_price numeric DEFAULT NULL::numeric, p_reason text DEFAULT '仕入価格表から再計算'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_move public.qr_lot_movements%rowtype;
  v_lot public.qr_lots%rowtype;
  v_price jsonb;
  v_found boolean:=false;
  v_unit numeric;
  v_amount numeric;
  v_weight numeric;
  v_pack_weight numeric;
  v_match_type text;
  v_match_reason text;
  v_source_supplier text;
  v_average_count integer:=0;
begin
  v_profile:=public.trimming_require_role(array['admin','sales','clerk']);

  select * into v_move
  from public.qr_lot_movements
  where id=p_movement_id
  for update;
  if not found then raise exception '対象のQR廃棄履歴が見つかりません' using errcode='P0002'; end if;
  if v_move.movement_type<>'廃棄' or v_move.cancelled_at is not null or v_move.reversed_operation_id is not null or public.seika_qr_operation_cancelled_v1162(v_move.operation_id::text) then
    raise exception '対象履歴は有効なQR廃棄ではありません' using errcode='22023';
  end if;

  select * into v_lot from public.qr_lots where id=v_move.lot_id limit 1;
  if not found then select * into v_lot from public.qr_lots where qr_key=v_move.qr_key limit 1; end if;
  if not found then raise exception '対象QRロットが見つかりません' using errcode='P0002'; end if;

  v_pack_weight:=public.seika_parse_kg_v1162(v_lot.pack_weight);
  v_weight:=coalesce(
    nullif(v_move.weight,0),
    case when v_move.before_weight is not null and v_move.after_weight is not null and abs(v_move.before_weight-v_move.after_weight)>0 then abs(v_move.before_weight-v_move.after_weight) end,
    case when v_pack_weight>0 and v_move.qty>0 then round(v_pack_weight*v_move.qty,3) end
  );
  if v_weight is null or v_weight<=0 then
    return jsonb_build_object('ok',true,'calculated',false,'reason','廃棄重量を確定できません。QRロットの量目または重量を確認してください');
  end if;

  if p_manual_unit_price is not null then
    if p_manual_unit_price<=0 then raise exception '手動単価は0より大きい値が必要です' using errcode='22023'; end if;
    if btrim(coalesce(p_reason,''))='' then raise exception '単価修正理由が必要です' using errcode='22023'; end if;
    v_found:=true;
    v_unit:=round(p_manual_unit_price,0);
    v_match_type:='手動修正';
    v_match_reason:=btrim(p_reason)||' / 実行者: '||coalesce(v_profile.display_name,v_profile.legacy_user_id,v_profile.id::text);
    v_source_supplier:='手動入力';
  else
    v_price:=public.resolve_trimming_purchase_price_v1117(
      v_lot.item_name,
      coalesce(v_lot.origin,''),
      coalesce(v_lot.supplier,''),
      coalesce((coalesce(v_move.occurred_at,v_move.created_at) at time zone 'Asia/Tokyo')::date,v_lot.received_date,current_date)
    );
    v_found:=coalesce((v_price->>'found')::boolean,false);
    if not v_found then
      return jsonb_build_object('ok',true,'calculated',false,'movement_id',v_move.id,'reason',coalesce(v_price->>'match_reason','同一品目の登録価格がありません'));
    end if;
    v_unit:=(v_price->>'price_yen_per_kg')::numeric;
    v_match_type:=coalesce(v_price->>'match_type','自動計算');
    v_match_reason:=coalesce(v_price->>'match_reason','仕入価格表から自動計算');
    v_source_supplier:=nullif(v_price->>'source_supplier','');
    v_average_count:=coalesce((v_price->>'average_count')::integer,0);
  end if;

  v_amount:=round(v_unit*v_weight,2);
  update public.qr_lot_movements
  set purchase_price_yen_per_kg=v_unit,
      waste_amount_yen=v_amount,
      price_match_type=v_match_type,
      price_match_reason=v_match_reason,
      price_source_supplier=v_source_supplier,
      price_average_count=v_average_count,
      price_reference_date=coalesce((coalesce(v_move.occurred_at,v_move.created_at) at time zone 'Asia/Tokyo')::date,v_lot.received_date,current_date),
      price_calculated_at=now()
  where id=v_move.id;

  return jsonb_build_object(
    'ok',true,'calculated',true,'movement_id',v_move.id,'weight_used_for_price',v_weight,
    'unit_price',v_unit,'amount',v_amount,'match_type',v_match_type,
    'reason',v_match_reason,'average_count',v_average_count
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.replace_trimming_job_outputs(p_job_id uuid, p_outputs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles; v_job public.trimming_jobs; x jsonb; v_mode text; v_weight numeric:=0; v_one numeric; v_qty numeric; v_unit numeric;
  v_item_id text; v_item_name text; v_state_row public.app_state; v_master jsonb;
begin
  v_profile:=public.trimming_require_role(array['admin','worker','buyer']);
  if jsonb_typeof(p_outputs)<>'array' or jsonb_array_length(p_outputs)=0 then raise exception '入替品が必要です' using errcode='22023'; end if;
  select * into v_job from public.trimming_jobs where id=p_job_id for update; if not found then raise exception 'トリミング記録が見つかりません' using errcode='22023'; end if;
  if exists(select 1 from public.trimming_job_outputs where trimming_job_id=p_job_id and apply_to_normal_inventory) then raise exception '通常在庫反映済みの記録は取消してから再登録してください' using errcode='22023'; end if;
  v_state_row:=public.trimming_lock_inventory_state();
  if jsonb_typeof(v_state_row.data->'items') <> 'array' then raise exception '通常在庫品目マスタが不正です' using errcode='22023'; end if;
  delete from public.trimming_job_outputs where trimming_job_id=p_job_id;
  for x in select value from jsonb_array_elements(p_outputs) loop
    v_mode:=x->>'mode'; v_item_id:=nullif(btrim(coalesce(x->>'item_id','')),'');
    if v_item_id is null or v_mode not in ('weight','qty') then raise exception '入替品の通常在庫品目とmodeが必要です' using errcode='22023'; end if;
    select i into v_master from jsonb_array_elements(v_state_row.data->'items') i where i->>'id'=v_item_id and coalesce((i->>'active')::boolean,true) limit 1;
    if v_master is null then raise exception '有効な通常在庫品目が見つかりません: %',v_item_id using errcode='22023'; end if;
    v_item_name:=btrim(v_master->>'name');
    if v_item_name='' or (position('入替品' in v_item_name)=0 and position('入れ替え品' in v_item_name)=0) or position(v_job.source_item_name in v_item_name)=0 then
      raise exception '入替品は元品目名を含む有効な「入替品」または「入れ替え品」の通常在庫品目を選択してください' using errcode='22023';
    end if;
    if v_mode='weight' then v_one:=(x->>'output_weight_kg')::numeric; v_qty:=null; v_unit:=null; else v_qty:=(x->>'output_qty')::numeric; v_unit:=(x->>'unit_weight_kg')::numeric; v_one:=round(v_qty*v_unit,3); end if;
    if v_one is null or v_one<=0 or (v_mode='qty' and (v_qty<=0 or v_unit<=0)) then raise exception '入替品の重量・数量が不正です' using errcode='22023'; end if;
    v_weight:=v_weight+v_one;
    insert into public.trimming_job_outputs(trimming_job_id,item_id,item_name,output_weight_kg,output_qty,unit_weight_kg,mode,apply_to_normal_inventory) values(p_job_id,v_item_id,v_item_name,v_one,v_qty,v_unit,v_mode,false);
  end loop;
  if v_weight>v_job.input_weight_kg+0.011 then raise exception '入替品合計重量が使用重量を超えています' using errcode='22023'; end if;
  update public.trimming_jobs set output_weight_kg=round(v_weight,3),loss_weight_kg=round(input_weight_kg-v_weight,3),yield_percent=round(v_weight/nullif(input_weight_kg,0)*100,3),updated_at=now() where id=p_job_id returning * into v_job;
  return jsonb_build_object('ok',true,'job',to_jsonb(v_job));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.replace_trimming_job_v1203(p_job_id text, p_operation_id text, p_work_date text, p_lots jsonb, p_outputs jsonb, p_note text DEFAULT ''::text, p_user_name text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_old   public.trimming_jobs;
  v_role  text;
  v_ans   jsonb;
  v_rows  integer;
begin
  begin
    v_role := public.current_app_role();
  exception when others then
    v_role := null;
  end;
  if v_role is not null and v_role not in ('admin','worker') then
    return jsonb_build_object('ok', false, 'message', '日報の修正は管理者・青果社員のみです。');
  end if;

  select * into v_old from public.trimming_jobs where id::text = p_job_id;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'もとの日報が見つかりません。画面を再読み込みしてください。');
  end if;

  -- 新しい内容で登録（既存の登録関数をそのまま使う）
  execute format(
    'select public.create_trimming_job('
    || 'p_operation_id := %L, p_work_date := %L, p_lots := %L, '
    || 'p_outputs := %L, p_note := %L, p_user_name := %L)',
    coalesce(nullif(p_operation_id,''), gen_random_uuid()::text),
    p_work_date,
    coalesce(p_lots, '[]'::jsonb)::text,
    coalesce(p_outputs, '[]'::jsonb)::text,
    coalesce(p_note, ''),
    coalesce(nullif(p_user_name,''), v_old.created_by_name, '')
  ) into v_ans;

  if v_ans is null or coalesce((v_ans->>'ok')::boolean, false) is not true then
    return jsonb_build_object(
      'ok', false,
      'message', coalesce(v_ans->>'message', '修正内容を登録できませんでした。もとの日報はそのまま残っています。')
    );
  end if;

  -- 登録できたので、もとの日報を削除
  v_rows := public.seika_delete_trimming_job_rows_v1203(p_job_id);
  if v_rows = 0 then
    raise exception 'もとの日報を削除できませんでした（job_id=%）', p_job_id;
  end if;

  return v_ans || jsonb_build_object(
    'ok', true,
    'replaced_job_id', p_job_id,
    'message', '日報を修正しました。'
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.request_fifo_mode_transition_v1136(p_target_mode text, p_reason text, p_confirm_all_target_policies boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype; n integer; coverage boolean; r public.seika_fifo_mode_transition_approvals_v1136%rowtype; begin
 v:=public.trimming_require_role(array['admin']);
 if p_target_mode not in ('warn','enforce') then raise exception '申請できる移行先はwarnまたはenforceです'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception '申請理由は1〜500文字で入力してください'; end if;
 if not coalesce(p_confirm_all_target_policies,false) then raise exception '全FIFO対象品目のポリシー確認チェックが必要です'; end if;
 select count(*) into n from public.seika_fifo_decision_audit_v1136 where mode='shadow';
 select not exists(
   select 1 from public.qr_lots q where q.active and q.status='在庫あり' and q.current_qty>0 and not exists(
    select 1 from public.seika_item_aging_policies_v1136 p where p.active and p.fifo_enabled and p.effective_from<=current_date and (p.effective_to is null or p.effective_to>=current_date)
      and ((nullif(btrim(coalesce(q.item_id,'')),'') is not null and nullif(btrim(coalesce(p.item_id,'')),'')=nullif(btrim(coalesce(q.item_id,'')),'') ) or
           (nullif(btrim(coalesce(q.item_id,'')),'') is null and nullif(btrim(coalesce(p.item_id,'')),'') is null and nullif(btrim(coalesce(p.item_name,'')),'')=nullif(btrim(coalesce(q.item_name,'')),'')))
   )
 ) into coverage;
 if n<20 then raise exception 'warn/enforce申請にはshadow監査が最低20件必要です（現在%件）',n; end if;
 if not coverage then raise exception '在庫中の全対象品目に有効FIFOポリシーがあることを確認できません'; end if;
 insert into public.seika_fifo_mode_transition_approvals_v1136(requested_by,target_mode,request_reason,requester_confirmed,shadow_audit_count_at_request,active_policy_coverage_ok_at_request)
 values(v.id,p_target_mode,btrim(p_reason),true,n,coverage) returning * into r;
 insert into public.seika_policy_audit_v1136(audited_by,audit_kind,subject_key,action,after_state,reason) values(v.id,'mode_transition',r.id::text,'request',to_jsonb(r),btrim(p_reason));
 return jsonb_build_object('ok',true,'request',to_jsonb(r)); end $function$
;
CREATE OR REPLACE FUNCTION public.resolve_trimming_purchase_price_v1117(p_item_name text, p_origin text, p_supplier text, p_received_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_names text[];
  v_week date;
  v_row public.purchase_prices%rowtype;
  v_price numeric;
  v_count integer:=0;
  v_market boolean;
  v_supplier text;
  v_origin text;
  -- 市場4社（別名を明示登録した完全一致リスト）
  -- 中央園芸／茨城中央園芸／飯山中央市場／中央VFS／市場商事 は契約産地のため含めない
  v_market_names constant text[]:=array['水戸大同','大同','水戸中央','中央','東一','シティ'];
begin
  if p_received_date is null or btrim(coalesce(p_item_name,''))='' then
    return jsonb_build_object('found',false,'match_type','未計算','match_reason','品目または入庫日がありません','average_count',0);
  end if;
  v_week:=public.trimming_week_start(p_received_date);
  v_origin:=coalesce(p_origin,'');
  v_supplier:=public.trimming_normalize_supplier_v1117(p_supplier);
  v_market:=v_supplier = any(v_market_names);
  v_names:=public.seika_item_name_group_v1200(p_item_name);

  if v_market then
    -- 市場価格：産地は一切見ない。当週が未登録なら直近の登録週を使う
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name = any(v_names)
      and pp.price_type='market'
      and public.trimming_normalize_supplier_v1117(pp.supplier)='市場'
    order by pp.week_start desc,pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','市場価格',
        'match_reason',concat(coalesce(p_supplier,''),'を仕入価格表の「市場」へ対応（産地不問）'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
  else
    -- 契約価格①：産地が一致するものを優先
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name = any(v_names)
      and pp.origin=v_origin
      and pp.price_type='contract'
      and public.trimming_normalize_supplier_v1117(pp.supplier)=v_supplier
    order by pp.week_start desc,pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','契約価格',
        'match_reason',concat('仕入先「',coalesce(p_supplier,''),'」の最新契約価格'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
    -- 契約価格②：産地が違う／空欄でも、同一品目・同一仕入先なら採用
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name = any(v_names)
      and pp.price_type='contract'
      and public.trimming_normalize_supplier_v1117(pp.supplier)=v_supplier
    order by pp.week_start desc,pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','契約価格',
        'match_reason',concat('仕入先「',coalesce(p_supplier,''),'」の最新契約価格（産地不問）'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
  end if;

  with latest as (
    select distinct on (pp.price_type,pp.origin,public.trimming_normalize_supplier_v1117(pp.supplier))
      pp.price_yen_per_kg
    from public.purchase_prices pp
    where pp.item_name = any(v_names) and pp.week_start<=v_week
    order by pp.price_type,pp.origin,public.trimming_normalize_supplier_v1117(pp.supplier),pp.week_start desc,pp.updated_at desc
  )
  select round(avg(price_yen_per_kg),0),count(*) into v_price,v_count from latest;
  if v_count>0 then
    return jsonb_build_object('found',true,'price_yen_per_kg',v_price,'match_type','同一品目平均',
      'match_reason',concat('市場・契約価格に該当なし。同一品目の有効価格',v_count,'件を平均して四捨五入'),
      'source_supplier','同一品目平均','source_week_start',v_week,'average_count',v_count);
  end if;
  return jsonb_build_object('found',false,'match_type','未計算','match_reason','同一品目の登録価格がありません','average_count',0);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.resolve_waste_purchase_price_v1118(p_item_name text, p_origin text, p_supplier text, p_waste_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;
begin
  v_profile:=public.trimming_require_role(array['admin','worker','clerk']);
  return public.resolve_trimming_purchase_price_v1117(p_item_name,p_origin,p_supplier,p_waste_date);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_admin_notices_v1147(p_id text, p_expected_version bigint, p_admin_notices jsonb, p_operation_logs jsonb, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_notice jsonb;
  v_notices jsonb:=coalesce(p_admin_notices,'[]'::jsonb);
  v_logs jsonb:=coalesce(p_operation_logs,'[]'::jsonb);
  v_new_data jsonb;
  v_version bigint;
begin
  if auth.uid() is null then
    raise exception 'ログイン情報を確認できません。再ログインしてください' using errcode='42501';
  end if;

  select * into v_profile
  from public.profiles
  where id=auth.uid() and active=true
  limit 1;

  if not found or lower(btrim(coalesce(v_profile.role::text,'')))<>'admin' then
    raise exception '管理者お知らせを保存できるのは管理者だけです' using errcode='42501';
  end if;

  if p_id is null or btrim(p_id)='' or p_expected_version is null then
    raise exception '状態IDまたは版番号が不正です' using errcode='22023';
  end if;
  if p_operation_id is null or btrim(p_operation_id)='' or char_length(p_operation_id)>200 then
    raise exception '操作IDが不正です' using errcode='22023';
  end if;
  if jsonb_typeof(v_notices)<>'array' or jsonb_typeof(v_logs)<>'array' then
    raise exception 'お知らせまたは操作履歴の形式が不正です' using errcode='22023';
  end if;
  if jsonb_array_length(v_notices)>100 then
    raise exception '登録できるお知らせは100件までです' using errcode='22023';
  end if;
  if pg_column_size(v_notices)>1048576 then
    raise exception 'お知らせデータが大きすぎます' using errcode='22023';
  end if;

  for v_notice in select value from jsonb_array_elements(v_notices)
  loop
    if jsonb_typeof(v_notice)<>'object'
       or nullif(btrim(v_notice->>'id'),'') is null
       or nullif(btrim(v_notice->>'title'),'') is null
       or nullif(btrim(v_notice->>'body'),'') is null
       or char_length(v_notice->>'id')>200
       or char_length(v_notice->>'title')>100
       or char_length(v_notice->>'body')>1000
       or (v_notice ? 'startsAt' and nullif(v_notice->>'startsAt','') is not null and (v_notice->>'startsAt') !~ '^\d{4}-\d{2}-\d{2}$')
       or (v_notice ? 'endsAt' and nullif(v_notice->>'endsAt','') is not null and (v_notice->>'endsAt') !~ '^\d{4}-\d{2}-\d{2}$')
    then
      raise exception 'お知らせデータの内容が不正です' using errcode='22023';
    end if;
  end loop;

  if exists(
    select 1 from jsonb_array_elements(v_notices) n
    group by n->>'id' having count(*)>1
  ) then
    raise exception '同じお知らせIDが重複しています' using errcode='22023';
  end if;

  select * into v_state
  from public.app_state
  where id=p_id
  for update;

  if not found then
    raise exception 'アプリ状態が見つかりません' using errcode='P0002';
  end if;

  if v_state.version is distinct from p_expected_version then
    return jsonb_build_object(
      'ok',false,
      'conflict',true,
      'version',v_state.version,
      'message','他の端末で更新されています。最新データと安全に統合して再送してください'
    );
  end if;

  select coalesce(jsonb_agg(value order by ord),'[]'::jsonb)
  into v_logs
  from jsonb_array_elements(v_logs) with ordinality q(value,ord)
  where ord>greatest(jsonb_array_length(v_logs)-500,0);

  v_new_data:=jsonb_set(coalesce(v_state.data,'{}'::jsonb),'{adminNotices}',v_notices,true);
  v_new_data:=jsonb_set(v_new_data,'{operationLogs}',v_logs,true);

  update public.app_state
  set data=v_new_data,
      version=version+1,
      updated_at=now()
  where id=v_state.id
  returning version into v_version;

  return jsonb_build_object(
    'ok',true,
    'conflict',false,
    'version',v_version,
    'operationId',p_operation_id
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_clerk_waste_history_v188(p_waste_records jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  x jsonb;
  v_existing public.waste_records%rowtype;
  v_clean_data jsonb;
begin
  select * into v_profile
  from public.profiles
  where id = auth.uid() and active = true;

  if not found then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if v_profile.role <> 'clerk' then
    raise exception '事務員専用の保存処理です' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_waste_records, '[]'::jsonb)) <> 'array' then
    raise exception '廃棄履歴は配列で指定してください' using errcode = '22023';
  end if;

  for x in select value from jsonb_array_elements(coalesce(p_waste_records, '[]'::jsonb)) loop
    if nullif(x->>'id', '') is null then
      raise exception '廃棄履歴IDが必要です' using errcode = '22023';
    end if;
    if coalesce((x->>'qty')::numeric, 0) < 0 or coalesce((x->>'unitPrice')::numeric, 0) < 0 then
      raise exception '数量または単価が正しくありません' using errcode = '22023';
    end if;

    select * into v_existing
    from public.waste_records
    where id = public.seika_uuid_v188(x->>'id')
    for update;

    if found then
      v_clean_data := coalesce(v_existing.data, '{}'::jsonb)
        || (x - 'user' - 'userId' - 'createdAt')
        || jsonb_build_object(
          'user', coalesce(v_existing.data->>'user', v_existing.user_name),
          'userId', coalesce(v_existing.data->>'userId', v_existing.user_id),
          'createdAt', coalesce(v_existing.data->>'createdAt', v_existing.created_at::text),
          'updatedAt', now()
        );

      update public.waste_records wr
      set waste_date = coalesce((x->>'date')::date, wr.waste_date),
          item_name = coalesce(nullif(x->>'itemName', ''), wr.item_name),
          qty = coalesce((x->>'qty')::numeric, wr.qty),
          unit_price = coalesce((x->>'unitPrice')::numeric, wr.unit_price),
          amount = coalesce((x->>'amount')::numeric, wr.amount),
          updated_at = now(),
          data = v_clean_data
      where wr.id = public.seika_uuid_v188(x->>'id');
    else
      v_clean_data := (x - 'user' - 'userId')
        || jsonb_build_object('user', v_profile.display_name, 'userId', v_profile.legacy_user_id);

      insert into public.waste_records(
        id, waste_date, item_name, qty, unit_price, amount,
        user_name, user_id, created_at, updated_at, data
      ) values (
        public.seika_uuid_v188(x->>'id'),
        coalesce((x->>'date')::date, current_date),
        x->>'itemName',
        coalesce((x->>'qty')::numeric, 0),
        coalesce((x->>'unitPrice')::numeric, 0),
        coalesce((x->>'amount')::numeric, 0),
        v_profile.display_name,
        v_profile.legacy_user_id,
        coalesce((x->>'createdAt')::timestamptz, now()),
        now(),
        v_clean_data
      );
    end if;
  end loop;

  return jsonb_build_object('ok', true);
end
$function$
;
CREATE OR REPLACE FUNCTION public.save_clerk_waste_state_v188(p_id text, p_expected_version bigint, p_waste_records jsonb DEFAULT '[]'::jsonb, p_operation_logs jsonb DEFAULT '[]'::jsonb, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_next_data jsonb;
  v_next_version bigint;
  v_operation_uuid uuid;
begin
  v_operation_uuid := case when nullif(trim(coalesce(p_operation_id,'')),'') is null then null else public.seika_uuid_v188(p_operation_id) end;
  select * into v_profile
  from public.profiles
  where id = auth.uid() and active = true;

  if not found then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if v_profile.role <> 'clerk' then
    raise exception '事務員専用の保存処理です' using errcode = '42501';
  end if;
  if p_id <> 'ishioka_inventory_production_v2' then
    raise exception '保存先が正しくありません' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_waste_records, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_operation_logs, '[]'::jsonb)) <> 'array' then
    raise exception '保存データは配列で指定してください' using errcode = '22023';
  end if;

  select * into v_state
  from public.app_state
  where id = p_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', '保存先が見つかりません');
  end if;
  if v_state.version is distinct from p_expected_version then
    return jsonb_build_object(
      'ok', false,
      'conflict', true,
      'code', 'VERSION_CONFLICT',
      'message', '他端末の更新があります',
      'version', v_state.version,
      'updated_at', v_state.updated_at
    );
  end if;
  if p_operation_id is not null and v_state.last_operation_id = v_operation_uuid then
    return jsonb_build_object('ok', true, 'duplicate', true, 'version', v_state.version);
  end if;

  v_next_data := coalesce(v_state.data, '{}'::jsonb);
  -- 通常保存では既存行の省略を削除と解釈しない。削除はdelete_clerk_waste_v188だけで行う。
  v_next_data := jsonb_set(
    v_next_data,
    '{wasteRecords}',
    coalesce((
      select jsonb_agg(v order by ord)
      from (
        select value as v, ordinality as ord
        from jsonb_array_elements(coalesce(v_next_data->'wasteRecords','[]'::jsonb)) with ordinality
        where not exists (
          select 1 from jsonb_array_elements(coalesce(p_waste_records,'[]'::jsonb)) incoming
          where incoming->>'id'=value->>'id'
        )
        union all
        select value, 1000000+ordinality
        from jsonb_array_elements(coalesce(p_waste_records,'[]'::jsonb)) with ordinality
      ) merged
    ), '[]'::jsonb),
    true
  );
  v_next_data := jsonb_set(
    v_next_data,
    '{operationLogs}',
    coalesce((
      select jsonb_agg(v order by ord)
      from (
        select value as v, ordinality as ord
        from jsonb_array_elements(coalesce(v_next_data->'operationLogs','[]'::jsonb)) with ordinality
        where not exists (
          select 1 from jsonb_array_elements(coalesce(p_operation_logs,'[]'::jsonb)) incoming
          where coalesce(incoming->>'operationId',incoming->>'id')=coalesce(value->>'operationId',value->>'id')
        )
        union all
        select value, 1000000+ordinality
        from jsonb_array_elements(coalesce(p_operation_logs,'[]'::jsonb)) with ordinality
      ) merged
    ), '[]'::jsonb),
    true
  );
  v_next_version := v_state.version + 1;

  update public.app_state
  set data = v_next_data,
      version = v_next_version,
      updated_at = now(),
      last_operation_id = v_operation_uuid,
      last_device_meta = coalesce(p_device_meta, '{}'::jsonb),
      last_operation_meta = coalesce(p_operation_meta, '{}'::jsonb)
  where id = p_id;

  return jsonb_build_object('ok', true, 'version', v_next_version, 'updated_at', now());
end
$function$
;
CREATE OR REPLACE FUNCTION public.save_history_records_v188(p_records jsonb DEFAULT '[]'::jsonb, p_waste_records jsonb DEFAULT '[]'::jsonb, p_movements jsonb DEFAULT '[]'::jsonb, p_delete_record_ids text[] DEFAULT '{}'::text[], p_delete_waste_ids text[] DEFAULT '{}'::text[], p_delete_movement_ids text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  x jsonb;
begin
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if v_profile.role not in ('admin','worker','sales') then raise exception '履歴保存権限がありません' using errcode='42501'; end if;
  if jsonb_typeof(p_records)<>'array' or jsonb_typeof(p_waste_records)<>'array' or jsonb_typeof(p_movements)<>'array' then raise exception '履歴は配列で指定してください' using errcode='22023'; end if;
  if v_profile.role='sales' and (jsonb_array_length(p_records)>0 or jsonb_array_length(p_movements)>0 or cardinality(p_delete_record_ids)>0 or cardinality(p_delete_waste_ids)>0 or cardinality(p_delete_movement_ids)>0) then raise exception '営業担当者は廃棄履歴の登録・修正のみ可能です' using errcode='42501'; end if;
  if v_profile.role='worker' and (cardinality(p_delete_record_ids)>0 or cardinality(p_delete_movement_ids)>0) then raise exception '青果社員は通常在庫履歴を削除できません' using errcode='42501'; end if;

  if v_profile.role='admin' then
    delete from public.inventory_records
     where id = any(array(select public.seika_uuid_v188(v)::text from unnest(coalesce(p_delete_record_ids,'{}')) v where nullif(trim(v),'') is not null));
    delete from public.inventory_movements
     where id = any(array(select public.seika_uuid_v188(v)::text from unnest(coalesce(p_delete_movement_ids,'{}')) v where nullif(trim(v),'') is not null));
  end if;
  if v_profile.role in ('admin','worker') then
    delete from public.waste_records
     where id = any(array(select public.seika_uuid_v188(v)::text from unnest(coalesce(p_delete_waste_ids,'{}')) v where nullif(trim(v),'') is not null));
  end if;

  if v_profile.role in ('admin','worker') then
    for x in select value from jsonb_array_elements(p_records) loop
      insert into public.inventory_records(id,item_id,item_name,kind,total,status,user_name,user_role,created_at,updated_at,data)
      values(public.seika_uuid_v188(x->>'id')::text,x->>'itemId',x->>'itemName',x->>'kind',coalesce((x->>'total')::numeric,0),x->>'status',coalesce(x->>'user',v_profile.display_name),v_profile.role,coalesce((x->>'createdAt')::timestamptz,now()),now(),x)
      on conflict(id) do update set item_id=excluded.item_id,item_name=excluded.item_name,kind=excluded.kind,total=excluded.total,status=excluded.status,updated_at=now(),data=excluded.data;
    end loop;
    for x in select value from jsonb_array_elements(p_movements) loop
      insert into public.inventory_movements(id,record_id,item_id,item_name,movement_type,before_total,after_total,diff_kg,user_name,user_role,created_at,data)
      values(public.seika_uuid_v188(x->>'id')::text,
             case when nullif(x->>'recordId','') is null then null else public.seika_uuid_v188(x->>'recordId')::text end,
             x->>'itemId',x->>'itemName',x->>'type',coalesce((x->>'beforeTotal')::numeric,0),coalesce((x->>'afterTotal')::numeric,0),coalesce((x->>'diffKg')::numeric,0),coalesce(x->>'user',v_profile.display_name),v_profile.role,coalesce((x->>'createdAt')::timestamptz,now()),x)
      on conflict(id) do update set record_id=excluded.record_id,item_id=excluded.item_id,item_name=excluded.item_name,movement_type=excluded.movement_type,before_total=excluded.before_total,after_total=excluded.after_total,diff_kg=excluded.diff_kg,data=excluded.data;
    end loop;
  end if;

  for x in select value from jsonb_array_elements(p_waste_records) loop
    if v_profile.role='sales' then
      if not exists(select 1 from public.waste_records where id=public.seika_uuid_v188(x->>'id')::text) then
        raise exception '営業担当者は廃棄履歴を新規作成できません' using errcode='42501';
      end if;
      update public.waste_records wr
      set unit_price=coalesce((x->>'unitPrice')::numeric,wr.unit_price),
          amount=coalesce((x->>'amount')::numeric,wr.amount),
          updated_at=now(),
          data=jsonb_set(jsonb_set(coalesce(wr.data,'{}'::jsonb),'{unitPrice}',to_jsonb(coalesce((x->>'unitPrice')::numeric,wr.unit_price)),true),'{amount}',to_jsonb(coalesce((x->>'amount')::numeric,wr.amount)),true)
      where wr.id=public.seika_uuid_v188(x->>'id')::text;
    else
      insert into public.waste_records(id,waste_date,item_name,qty,unit_price,amount,user_name,user_id,created_at,updated_at,data)
      values(public.seika_uuid_v188(x->>'id')::text,coalesce((x->>'date')::date,current_date),coalesce(nullif(x->>'itemName',''),'-'),coalesce((x->>'qty')::numeric,0),coalesce((x->>'unitPrice')::numeric,0),coalesce((x->>'amount')::numeric,0),coalesce(x->>'user',v_profile.display_name),coalesce(x->>'userId',v_profile.legacy_user_id),coalesce((x->>'createdAt')::timestamptz,now()),now(),x)
      on conflict(id) do update set waste_date=excluded.waste_date,item_name=excluded.item_name,qty=excluded.qty,unit_price=excluded.unit_price,amount=excluded.amount,updated_at=now(),data=excluded.data;
    end if;
  end loop;

  return jsonb_build_object('ok',true);
end
$function$
;
CREATE OR REPLACE FUNCTION public.save_qr_lot_edit_history_v1158(p_operation_id uuid, p_history jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_existing public.qr_lot_movements%rowtype;
  v_movement public.qr_lot_movements%rowtype;
  v_qr_key text := nullif(btrim(coalesce(p_history ->> 'qr_key', '')), '');
  v_reason text := nullif(btrim(coalesce(p_history ->> 'reason', '')), '');
  v_memo text := nullif(btrim(coalesce(p_history ->> 'memo', '')), '');
begin
  v_profile := public.trimming_require_role(array['admin','worker']);

  if p_operation_id is null then
    raise exception 'operation_id は必須です' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_history, '{}'::jsonb)) <> 'object' then
    raise exception '訂正履歴の形式が不正です' using errcode = '22023';
  end if;
  if v_qr_key is null then
    raise exception 'qr_key は必須です' using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception '変更理由は必須です' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 or char_length(coalesce(v_memo, '')) > 2000 then
    raise exception '訂正履歴の文字数が上限を超えています' using errcode = '22023';
  end if;

  select * into v_existing
    from public.qr_lot_movements
   where operation_id = p_operation_id;
  if found then
    if v_existing.qr_key is distinct from v_qr_key
       or v_existing.movement_type is distinct from 'ロット情報訂正' then
      return jsonb_build_object(
        'ok', false,
        'idempotency_conflict', true,
        'message', '同じoperation_idの既存履歴と訂正内容が一致しません。管理者へ連絡してください。'
      );
    end if;
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'movement_id', v_existing.id
    );
  end if;

  select * into v_lot
    from public.qr_lots
   where qr_key = v_qr_key
     and coalesce(active, true) = true
   order by created_at desc, id desc
   limit 1;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'not_found', true,
      'message', '対象QRロットが見つかりません。再読込して確認してください。'
    );
  end if;

  insert into public.qr_lot_movements(
    movement_type, lot_id, lot_no, qr_key, item_id, item_name,
    origin, supplier, cooperative_name, qty, unit, storage_location,
    user_id, user_name, memo, container_type, lot_manage_type,
    before_quantity, after_quantity, before_weight, after_weight,
    weight_status, reason, operation_id, device_meta, operation_meta
  ) values (
    'ロット情報訂正', v_lot.id, v_lot.lot_no, v_lot.qr_key,
    v_lot.item_id,
    v_lot.item_name,
    v_lot.origin,
    v_lot.supplier,
    v_lot.cooperative_name,
    0,
    v_lot.unit,
    v_lot.storage_location,
    v_profile.id::text,
    coalesce(v_profile.display_name, ''),
    v_memo,
    v_lot.container_type,
    v_lot.lot_manage_type,
    coalesce(v_lot.current_qty, 0),
    coalesce(v_lot.current_qty, 0),
    v_lot.current_weight,
    v_lot.current_weight,
    v_lot.weight_status,
    v_reason,
    p_operation_id,
    jsonb_build_object('user_agent', left(coalesce(p_history ->> 'user_agent', ''), 500)),
    jsonb_build_object('source', 'qr_lot_edit', 'version', 'v1.158')
  )
  returning * into v_movement;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'movement_id', v_movement.id
  );
exception
  when unique_violation then
    select * into v_existing
      from public.qr_lot_movements
     where operation_id = p_operation_id;
    if found
       and v_existing.qr_key = v_qr_key
       and v_existing.movement_type = 'ロット情報訂正' then
      return jsonb_build_object('ok', true, 'idempotent', true, 'movement_id', v_existing.id);
    end if;
    raise;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_qr_lot_edit_history_v1159(p_operation_id uuid, p_history jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_existing public.qr_lot_movements%rowtype;
  v_movement public.qr_lot_movements%rowtype;
  v_qr_key text;
  v_reason text;
  v_memo text;
begin
  v_profile := public.seika_v1159_qr_operator();
  if p_operation_id is null then raise exception 'operation_idは必須です' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_history,'{}'::jsonb)) <> 'object' then raise exception '訂正履歴の形式が不正です' using errcode='22023'; end if;

  v_qr_key := nullif(btrim(coalesce(p_history->>'qr_key','')),'');
  v_reason := nullif(btrim(coalesce(p_history->>'reason','')),'');
  v_memo := nullif(btrim(coalesce(p_history->>'memo','')),'');
  if v_qr_key is null then raise exception 'qr_keyは必須です' using errcode='22023'; end if;
  if v_reason is null then raise exception '変更理由は必須です' using errcode='22023'; end if;
  if char_length(v_reason)>500 or char_length(coalesce(v_memo,''))>2000 then raise exception '訂正履歴の文字数が上限を超えています' using errcode='22023'; end if;

  select * into v_existing from public.qr_lot_movements where operation_id=p_operation_id;
  if found then
    if v_existing.qr_key is distinct from v_qr_key or v_existing.movement_type is distinct from 'ロット情報訂正' then
      return jsonb_build_object('ok',false,'error_code','IDEMPOTENCY_CONFLICT','message','同じ操作IDの既存履歴と訂正内容が一致しません。管理者へ連絡してください。');
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'movement_id',v_existing.id);
  end if;

  select * into v_lot
  from public.qr_lots
  where qr_key=v_qr_key
  order by coalesce(active,true) desc, created_at desc, id desc
  limit 1;
  if not found then
    return jsonb_build_object('ok',false,'error_code','LOT_NOT_FOUND','message','対象QRロットが見つかりません。QRロット一覧を再読込してください。');
  end if;

  insert into public.qr_lot_movements(
    movement_type,lot_id,lot_no,qr_key,item_id,item_name,origin,supplier,cooperative_name,
    qty,unit,storage_location,user_id,user_name,memo,container_type,lot_manage_type,
    before_quantity,after_quantity,before_weight,after_weight,weight_status,reason,
    operation_id,device_meta,operation_meta
  ) values (
    'ロット情報訂正',v_lot.id,v_lot.lot_no,v_lot.qr_key,v_lot.item_id,v_lot.item_name,
    v_lot.origin,v_lot.supplier,v_lot.cooperative_name,0,v_lot.unit,v_lot.storage_location,
    v_profile.id::text,coalesce(v_profile.display_name,''),v_memo,v_lot.container_type,v_lot.lot_manage_type,
    coalesce(v_lot.current_qty,0),coalesce(v_lot.current_qty,0),v_lot.current_weight,v_lot.current_weight,
    v_lot.weight_status,v_reason,p_operation_id,
    jsonb_build_object('user_agent',left(coalesce(p_history->>'user_agent',''),500)),
    jsonb_build_object('source','qr_lot_edit','version','v1.159')
  ) returning * into v_movement;

  return jsonb_build_object('ok',true,'idempotent',false,'movement_id',v_movement.id);
exception
  when unique_violation then
    select * into v_existing from public.qr_lot_movements where operation_id=p_operation_id;
    if found and v_existing.qr_key=v_qr_key and v_existing.movement_type='ロット情報訂正' then
      return jsonb_build_object('ok',true,'idempotent',true,'movement_id',v_existing.id);
    end if;
    raise;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_admin_notice_audit_guard_v1150()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception 'seika_admin_notice_audit_v1150 は追記専用です。UPDATE、DELETE、TRUNCATEは許可されません。'
    using errcode='42501';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_admin_notice_require_admin_v1150()
 RETURNS TABLE(actor_id uuid, actor_role text, actor_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'ログイン情報を確認できません。再ログインしてください' using errcode='42501';
  end if;

  select * into v_profile
  from public.profiles
  where id = auth.uid()
    and active = true
  limit 1;

  if not found or lower(btrim(coalesce(v_profile.role::text, ''))) <> 'admin' then
    raise exception '管理者お知らせを操作できるのは有効な管理者だけです' using errcode='42501';
  end if;

  v_name := coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'name', ''),
    nullif(auth.jwt() -> 'user_metadata' ->> 'full_name', ''),
    auth.uid()::text
  );
  return query select auth.uid(), v_profile.role::text, left(v_name, 300);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_admin_notice_sync_app_state_v1150(p_state_id text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_notices jsonb;
  v_version bigint;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', n.notice_id,
        'title', n.title,
        'body', n.body,
        'startsAt', n.starts_at,
        'endsAt', n.ends_at,
        'active', n.active,
        'createdAt', n.created_at,
        'createdBy', n.created_by,
        'createdById', n.created_by_id,
        'updatedAt', n.updated_at
      ) order by n.created_at desc, n.notice_id desc
    ),
    '[]'::jsonb
  )
  into v_notices
  from public.seika_admin_notices_v1150 n
  where n.state_id = p_state_id;

  update public.app_state
  set data = jsonb_set(coalesce(data, '{}'::jsonb), '{adminNotices}', v_notices, true),
      version = version + 1,
      updated_at = now()
  where id = p_state_id
  returning version into v_version;

  if not found then
    raise exception 'アプリ状態が見つかりません' using errcode='P0002';
  end if;
  return v_version;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_archive_module_allowed_v1101(p_module text, p_role text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case lower(btrim(coalesce(p_module, '')))
    when 'waste' then lower(btrim(coalesce(p_role, ''))) = any(array['admin','worker','sales','clerk'])
    when 'qr' then lower(btrim(coalesce(p_role, ''))) = any(array['admin','worker','clerk'])
    when 'trimming' then lower(btrim(coalesce(p_role, ''))) = any(array['admin','worker','buyer','clerk'])
    when 'quality' then lower(btrim(coalesce(p_role, ''))) = any(array['admin','worker','clerk'])
    else false
  end
$function$
;
CREATE OR REPLACE FUNCTION public.seika_archive_profile_v1101()
 RETURNS profiles
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.seika_current_profile_v1145()
$function$
;
CREATE OR REPLACE FUNCTION public.seika_current_profile_v1145()
 RETURNS profiles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_auth_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_auth_id is null then
    raise exception 'ログイン情報を確認できません。再ログインしてください'
      using errcode = '42501';
  end if;

  select p.*
  into v_profile
  from public.get_my_profile() gp
  join public.profiles p on p.id = gp.id
  where p.id = v_auth_id
  limit 1;

  if not found then
    raise exception 'Auth UUIDに対応するプロフィールがありません。get_my_profile()とprofilesを確認してください'
      using errcode = '42501';
  end if;

  if v_profile.id is distinct from v_auth_id then
    raise exception 'プロフィールとログイン情報が一致しません。profiles.idを確認してください'
      using errcode = '42501';
  end if;

  if v_profile.active is distinct from true then
    raise exception 'このプロフィールは利用停止中です'
      using errcode = '42501';
  end if;

  if nullif(btrim(v_profile.role::text), '') is null then
    raise exception 'プロフィールの権限が未設定です。profiles.roleを確認してください'
      using errcode = '42501';
  end if;

  return v_profile;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_delete_trimming_job_rows_v1203(p_job_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
  v_deleted integer := 0;
  v_n integer;
begin
  for r in
    select c.conrelid::regclass as child_table,
           a.attname            as child_column
      from pg_constraint c
      join pg_attribute a
        on a.attrelid = c.conrelid
       and a.attnum   = c.conkey[1]
     where c.contype = 'f'
       and c.confrelid = 'public.trimming_jobs'::regclass
       and array_length(c.conkey, 1) = 1
  loop
    execute format('delete from %s where %I::text = $1', r.child_table, r.child_column)
      using p_job_id;
    get diagnostics v_n = row_count;
    v_deleted := v_deleted + v_n;
  end loop;

  delete from public.trimming_jobs where id::text = p_job_id;
  get diagnostics v_n = row_count;
  v_deleted := v_deleted + v_n;

  return v_deleted;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_enqueue_low_quality_push_v1144()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_lot record;
declare v_ctx jsonb;
declare v_buyer jsonb;
declare v_grade_label text;
declare v_item_name text;
declare v_lot_no text;
declare v_payload jsonb;
begin
  if new.grade not in ('review', 'bad')
     or new.active is not true
     or new.invalidated_at is not null
     or coalesce(new.invalidated_by_lot_delete, false) then
    return new;
  end if;

  select * into v_lot
  from public.seika_v1144_resolve_quality_lot(new.lot_id::text, new.qr_key)
  limit 1;
  if not found then
    return new;
  end if;

  select public.seika_quality_buyer_context_for_item_v1144(v_lot.lot_id, coalesce(v_lot.item_name, new.item_name))
  into v_ctx;
  v_grade_label := case new.grade when 'bad' then '不良' else '要確認' end;
  select coalesce(nullif(btrim(q.item_name), ''), nullif(btrim(new.item_name), ''), v_lot.item_name, '品名未設定'),
         coalesce(nullif(btrim(q.lot_no), ''), 'ロット番号未設定')
  into v_item_name, v_lot_no
  from public.qr_lots q where q.id = v_lot.lot_id;

  v_payload := jsonb_build_object(
    'evaluationId', new.id,
    'grade', new.grade,
    'title', 'SEIKA＋ 品質評価',
    'body', '【' || v_grade_label || '】' || v_item_name || '（' || v_lot_no || '）を確認してください',
    'url', './?open=quality&evaluation=' || new.id::text,
    'itemName', v_item_name,
    'lotNo', v_lot_no
  );

  for v_buyer in select value from jsonb_array_elements(coalesce(v_ctx -> 'buyers', '[]'::jsonb)) loop
    insert into public.quality_push_queue_v1144(
      evaluation_id, recipient_profile_id, subscription_id, grade, payload
    )
    select new.id, p.id, s.id, new.grade, v_payload
    from public.profiles p
    join public.web_push_subscriptions_v1144 s on s.profile_id = p.id and s.active
    where p.id = nullif(v_buyer ->> 'profile_id', '')::uuid
      and coalesce((v_buyer ->> 'can_acknowledge')::boolean, false)
      and p.active and p.role = 'buyer'
    on conflict (evaluation_id, subscription_id) do nothing;
  end loop;
  return new;
exception when others then
  -- 通知機構の不調で品質評価登録を失敗させない。
  raise warning 'SEIKA quality push enqueue skipped: %', sqlerrm;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_fifo_assess_lot_v1136(p_qr_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;t public.qr_lots%rowtype;p public.seika_item_aging_policies_v1136%rowtype; outj jsonb;begin
 v:=public.seika_v1136_active_profile();select * into t from public.qr_lots q where q.qr_key=nullif(btrim(coalesce(p_qr_key,'')),'') and q.active=true; if not found then return jsonb_build_object('ok',false,'message','対象QRロットが見つかりません');end if;
 select * into p from public.seika_item_aging_policies_v1136 x where x.active and x.effective_from<=current_date and(x.effective_to is null or x.effective_to>=current_date)and((nullif(btrim(coalesce(t.item_id,'')),'') is not null and nullif(btrim(coalesce(x.item_id,'')),'')=nullif(btrim(coalesce(t.item_id,'')),'') )or(nullif(btrim(coalesce(t.item_id,'')),'') is null and nullif(btrim(coalesce(x.item_id,'')),'') is null and nullif(btrim(coalesce(x.item_name,'')),'')=nullif(btrim(coalesce(t.item_name,'')),'')))order by case when nullif(btrim(coalesce(x.item_id,'')),'')is not null then 0 else 1 end,x.effective_from desc,x.created_at desc limit 1;
 if not found or not p.fifo_enabled then return jsonb_build_object('ok',true,'policy_applicable',false,'target_lot_id',t.id,'target_exclusion_reason','not_equivalent','message',case when not found then '有効なFIFOポリシーは未設定です' else 'この品目はFIFO対象外です'end,'candidates','[]'::jsonb);end if;
 with latest_quality as (
  select distinct on(e.qr_key)e.qr_key,e.id,e.grade,e.evaluated_at from public.qr_quality_evaluations e where e.active=true and e.invalidated_at is null and e.invalidated_by_lot_delete=false and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and n.active=true and n.invalidated_at is null and n.invalidated_by_lot_delete=false) order by e.qr_key,e.evaluated_at desc,e.created_at desc,e.id desc
 ), item_pool as (
  select q.*,l.id quality_evaluation_id,coalesce(l.grade,'unassessed') quality_grade,coalesce(h.active,false) held,
   (nullif(btrim(coalesce(q.origin,'')),'') is not distinct from nullif(btrim(coalesce(t.origin,'')),'') and nullif(btrim(coalesce(q.supplier,'')),'') is not distinct from nullif(btrim(coalesce(t.supplier,'')),'') and nullif(btrim(coalesce(q.cooperative_name,'')),'') is not distinct from nullif(btrim(coalesce(t.cooperative_name,'')),'') and nullif(btrim(coalesce(q.container_type,'')),'') is not distinct from nullif(btrim(coalesce(t.container_type,'')),'') and nullif(btrim(coalesce(q.lot_manage_type,'')),'') is not distinct from nullif(btrim(coalesce(t.lot_manage_type,'')),'') and nullif(btrim(coalesce(q.pack_weight,'')),'') is not distinct from nullif(btrim(coalesce(t.pack_weight,'')),'') and nullif(btrim(coalesce(q.unit,'')),'') is not distinct from nullif(btrim(coalesce(t.unit,'')),'') and nullif(btrim(coalesce(q.storage_location,'')),'') is not distinct from nullif(btrim(coalesce(t.storage_location,'')),'') ) eq
  from public.qr_lots q left join latest_quality l on l.qr_key=q.qr_key left join public.seika_fifo_lot_holds_v1136 h on h.lot_id=q.id and h.active
  where (case when nullif(btrim(coalesce(t.item_id,'')),'') is not null then nullif(btrim(coalesce(q.item_id,'')),'')=nullif(btrim(coalesce(t.item_id,'')),'') else nullif(btrim(coalesce(q.item_id,'')),'') is null and nullif(btrim(coalesce(q.item_name,'')),'')=nullif(btrim(coalesce(t.item_name,'')),'') end)
 ), classified as (
  select *,case when not eq then 'not_equivalent' when not active then 'inactive' when status<>'在庫あり' then 'not_in_stock_status' when current_qty<=0 then 'no_available_quantity' when quality_grade='bad' then 'quality_bad' when held then 'hold' else null end exclusion_reason from item_pool
 ), eligible as (select *,row_number()over(order by received_date,created_at,id) candidate_rank from classified where exclusion_reason is null), target as (select * from classified where id=t.id)
 select jsonb_build_object('ok',true,'policy_applicable',true,'policy_id',p.id,'quality_review_requires_confirmation',p.quality_review_requires_confirmation,'target_lot_id',t.id,'target',coalesce((select jsonb_build_object('lot_id',id,'qr_key',qr_key,'quality_evaluation_id',quality_evaluation_id,'quality_grade',quality_grade,'held',held,'exclusion_reason',exclusion_reason)from target),'{}'::jsonb),'recommended_lot_id',(select id from eligible where candidate_rank=1),'selected_rank',(select candidate_rank from eligible where id=t.id),'eligible_count',(select count(*)from eligible),'exclusion_summary',(select jsonb_object_agg(k,c)from(select exclusion_reason k,count(*)c from classified where exclusion_reason is not null group by exclusion_reason)s),'comparison_attributes',jsonb_build_array('item_id（未設定時はitem_name）','origin','supplier','cooperative_name','container_type','lot_manage_type','pack_weight','unit','storage_location（既存文字列の一致のみ）'),'candidates',coalesce((select jsonb_agg(jsonb_build_object('lot_id',id,'qr_key',qr_key,'lot_no',lot_no,'received_date',received_date,'age_days',greatest(0,current_date-received_date),'current_qty',current_qty,'unit',unit,'quality_evaluation_id',quality_evaluation_id,'quality_grade',quality_grade,'held',held,'candidate_rank',candidate_rank,'recommendation_reason','同一の品目・取引条件・荷姿等で出庫可能なロットのうち入庫日が古い順です')order by candidate_rank)from eligible),'[]'::jsonb)) into outj;
 return outj;end $function$
;
CREATE OR REPLACE FUNCTION public.seika_guard_old_waste_delete_v1101()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (old.waste_date is null or old.waste_date < (date_trunc('month',current_date)-interval '3 months')::date)
     and coalesce(current_setting('seika.monthly_archive_purge',true),'') <> 'on' then
    raise exception '3ãæè¶ã®å»æ£å±¥æ­´ã¯ææ¬¡Excelç®¡çããã®ã¿åé¤ã§ãã¾ã' using errcode='42501';
  end if;
  return old;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_decimal_optional_v123(p_value text, p_field text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_text text:=btrim(coalesce(p_value,'')); v_number numeric;
begin
  if v_text='' then return null; end if;
  if v_text~'、' then raise exception '% は数値として入力してください',p_field using errcode='22023';end if;
  v_text:=translate(v_text,'０１２３４５６７８９．，','0123456789.,');
  if v_text !~ '^(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?$' and v_text !~ '^\.[0-9]+$' then raise exception '% は正しい数値で入力してください',p_field using errcode='22023';end if;
  v_number:=replace(v_text,',','')::numeric;
  if abs(v_number)>100000000 then raise exception '% の値が不正です',p_field using errcode='22023';end if;
  return round(v_number,3);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_decimal_v1119(p_value text, p_field text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_text text:=btrim(coalesce(p_value,'')); v_number numeric;
begin
  if v_text='' then raise exception '% は必須です',p_field using errcode='22023'; end if;
  if v_text~'、' then raise exception '% は数値として入力してください',p_field using errcode='22023'; end if;
  v_text:=translate(v_text,'０１２３４５６７８９．，','0123456789.,');
  if v_text !~ '^(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?$' and v_text !~ '^\.[0-9]+$' then raise exception '% は正しい桁区切りまたは小数で入力してください',p_field using errcode='22023'; end if;
  v_number:=replace(v_text,',','')::numeric;
  if v_number<>v_number or abs(v_number)>100000000 then raise exception '% の値が不正です',p_field using errcode='22023'; end if;
  return round(v_number,3);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_line_kg_v1119(p_line jsonb, p_is_qr boolean)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_actual numeric; v_weight numeric; v_initial numeric; v_total_weight numeric; v_pack text; v_container text:=coalesce(p_line->>'containerType',''); v_explicit numeric;
begin
  v_actual:=public.seika_inventory_count_decimal_v1119(p_line->>'actualQty','棚卸し実数');
  if v_actual<0 then raise exception '棚卸し実数は0以上です' using errcode='22023'; end if;
  if not p_is_qr and coalesce(p_line->>'unit','kg')='kg' then return v_actual; end if;
  if p_is_qr and v_container in ('網コンテナ','鉄コンテナ','パレテーナ') then
    v_total_weight:=nullif(btrim(coalesce(p_line->>'snapshotTotalWeight','')),'')::numeric;
    v_initial:=nullif(btrim(coalesce(p_line->>'snapshotInitialQty','')),'')::numeric;
    if v_total_weight is not null and v_total_weight>0 and v_initial is not null and v_initial>0 then return round(v_actual*v_total_weight/v_initial,3); end if;
    v_weight:=public.seika_inventory_count_decimal_v1119(p_line->>'actualWeightKg','大型容器の棚卸し重量');
    if v_weight<0 then raise exception '大型容器の棚卸し重量は0以上です' using errcode='22023'; end if;
    return v_weight;
  end if;
  v_explicit:=case when nullif(btrim(coalesce(p_line->>'kgPerUnit','')),'') is not null then public.seika_inventory_count_decimal_v1119(p_line->>'kgPerUnit','1単位あたりkg') end;
  if v_explicit is not null and v_explicit>0 then return round(v_actual*v_explicit,3); end if;
  if p_is_qr then
    v_pack:=btrim(coalesce(p_line->>'packWeight',''));
    if v_pack~'^[0-9]+(?:\.[0-9]+)?[[:space:]]*[kK][gG]$' then return round(v_actual*regexp_replace(v_pack,'[[:space:]]*[kK][gG]$','')::numeric,3); end if;
  end if;
  raise exception 'kg換算できない行があります。1単位あたりkg、またはQR内容量を確認してください' using errcode='22023';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_lock_v1119(p_id text, p_expected_version bigint)
 RETURNS app_state
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_state public.app_state%rowtype;
begin
  if p_id is null or btrim(p_id)='' then raise exception '棚卸し状態IDが不正です' using errcode='22023'; end if;
  select * into v_state from public.app_state where id=p_id for update;
  if not found then raise exception '棚卸し状態データが見つかりません' using errcode='P0002'; end if;
  if p_expected_version is null or v_state.version<>p_expected_version then
    return null;
  end if;
  if jsonb_typeof(v_state.data->'inventoryCounts'->'sessions')<>'array' then
    raise exception '棚卸しセッションのデータ形式が不正です' using errcode='22023';
  end if;
  return v_state;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_normalize_session_v123(p_session jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_test boolean:=coalesce((p_session->>'isTest')::boolean,false);v_status text:=coalesce(p_session->>'status','');v_normal text;v_qr text;v_lines jsonb:='[]'::jsonb;v_line jsonb;v_entries jsonb;v_actual numeric;v_pack numeric;v_cases numeric;
begin
  v_normal:=coalesce(nullif(p_session->>'normalStatus',''),case when v_status in ('confirmed','test_confirmed') then 'confirmed' when v_status in ('submitted','test_submitted') then 'submitted' else 'counting' end);
  v_qr:=coalesce(nullif(p_session->>'qrCountStatus',''),case when v_status in ('confirmed','test_confirmed') then 'confirmed' when v_status in ('submitted','test_submitted') then 'submitted' else 'counting' end);
  for v_line in select value from jsonb_array_elements(coalesce(p_session->'lines','[]'::jsonb)) loop
    if lower(coalesce(v_line->>'unit','kg'))='kg' or coalesce(v_line->>'type','')='normal' then
      if jsonb_typeof(v_line->'weightEntries')='array' and jsonb_array_length(v_line->'weightEntries')>0 then v_entries:=v_line->'weightEntries';
      else
        v_actual:=public.seika_inventory_count_decimal_optional_v123(v_line->>'actualQty','実数');
        v_pack:=public.seika_inventory_count_decimal_optional_v123(v_line->>'packKg','量目kg');
        v_cases:=public.seika_inventory_count_decimal_optional_v123(v_line->>'caseCount','ケース数');
        if v_pack is not null and v_pack>0 and v_cases is not null and v_cases>=0 then
          v_entries:=jsonb_build_array(jsonb_build_object('id','legacy-1','packKg',v_pack,'caseCount',v_cases));
        elsif v_actual is not null then
          -- Legacy total input: exact total is preserved as one量目×1ケース (0 is 1kg×0ケース).
          v_entries:=jsonb_build_array(jsonb_build_object('id','legacy-1','packKg',case when v_actual>0 then v_actual else 1 end,'caseCount',case when v_actual>0 then 1 else 0 end));
        else v_entries:=jsonb_build_array(jsonb_build_object('id','w-1','packKg','','caseCount',''));
        end if;
      end if;
      v_line:=v_line||jsonb_build_object('inputMode','weight_entries','weightEntries',v_entries,'remainderKg',coalesce(v_line->'remainderKg','""'::jsonb));
    end if;
    v_lines:=v_lines||jsonb_build_array(v_line);
  end loop;
  p_session:=p_session||jsonb_build_object('countSchemaVersion',123,'lines',v_lines,'normalStatus',v_normal,'qrCountStatus',v_qr,'normalRevision',greatest(coalesce((p_session->>'normalRevision')::bigint,0),coalesce((p_session->>'revision')::bigint,0)),'qrRevision',greatest(coalesce((p_session->>'qrRevision')::bigint,0),coalesce((p_session->>'revision')::bigint,0)));
  return p_session||jsonb_build_object('status',public.seika_inventory_count_v123_status(p_session));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_normalize_session_v124(p_session jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_session jsonb:=public.seika_inventory_count_normalize_session_v123(p_session);v_normal jsonb:='[]'::jsonb;v_kataoka jsonb:='[]'::jsonb;v_seen jsonb:='{}'::jsonb;v_line jsonb;v_id text;v_kstatus text;
begin
 if coalesce(v_session->>'room','')='room2' then
  for v_line in select value from jsonb_array_elements(coalesce(v_session->'kataokaLines','[]'::jsonb)) loop
   v_id:=nullif(btrim(coalesce(v_line->>'lineId',v_line->>'id')),'');
   if v_id is not null and not (v_seen ? v_id) then v_seen:=v_seen||jsonb_build_object(v_id,true);v_kataoka:=v_kataoka||jsonb_build_array(v_line);end if;
  end loop;
  for v_line in select value from jsonb_array_elements(coalesce(v_session->'lines','[]'::jsonb)) loop
   if coalesce(v_line->>'type','')='special' and coalesce(v_line->>'tableId','')='kataoka' then
    v_id:=nullif(btrim(coalesce(v_line->>'lineId',v_line->>'id')),'');
    if v_id is not null and not (v_seen ? v_id) then v_seen:=v_seen||jsonb_build_object(v_id,true);v_kataoka:=v_kataoka||jsonb_build_array(v_line);end if;
   else v_normal:=v_normal||jsonb_build_array(v_line);end if;
  end loop;
  v_kstatus:=coalesce(nullif(v_session->>'kataokaStatus',''),case when v_session->>'status' in ('confirmed','test_confirmed') then 'confirmed' else 'counting' end);
  v_session:=v_session||jsonb_build_object('lines',v_normal,'kataokaLines',v_kataoka,'kataokaStatus',v_kstatus,'kataokaRevision',greatest(coalesce((v_session->>'kataokaRevision')::bigint,0),coalesce((v_session->>'revision')::bigint,0)),'countSchemaVersion',124);
 else v_session:=v_session||jsonb_build_object('kataokaLines','[]'::jsonb,'countSchemaVersion',124);end if;
 return v_session||jsonb_build_object('status',public.seika_inventory_count_v124_status(v_session));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_profile_v1119()
 RETURNS profiles
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.seika_current_profile_v1145()
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_profile_v123()
 RETURNS profiles
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.seika_current_profile_v1145()
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_replace_session_v1119(p_data jsonb, p_session_id text, p_session jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_set(
    p_data,
    '{inventoryCounts,sessions}',
    (
      select jsonb_agg(case when value->>'id'=p_session_id then p_session else value end)
      from jsonb_array_elements(coalesce(p_data->'inventoryCounts'->'sessions','[]'::jsonb))
    ),
    true
  )
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_session_v1119(p_data jsonb, p_session_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_session jsonb;
begin
  if p_session_id is null or btrim(p_session_id)='' or char_length(p_session_id)>160 then raise exception '棚卸しセッションIDが不正です' using errcode='22023'; end if;
  select value into v_session from jsonb_array_elements(coalesce(p_data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id limit 1;
  if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002'; end if;
  return v_session;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v123_append_log(p_data jsonb, p_event jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 with x as (select coalesce(p_data->'operationLogs','[]'::jsonb)||jsonb_build_array(p_event) as rows),
 y as (select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) rows from x,jsonb_array_elements(x.rows) with ordinality q(value,ord) where ord>greatest(jsonb_array_length(x.rows)-500,0))
 select jsonb_set(p_data,'{operationLogs}',y.rows,true) from y
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v123_replace_session(p_data jsonb, p_id text, p_session jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select jsonb_set(p_data,'{inventoryCounts,sessions}',coalesce((select jsonb_agg(case when value->>'id'=p_id then p_session else value end order by ord) from jsonb_array_elements(coalesce(p_data->'inventoryCounts'->'sessions','[]'::jsonb)) with ordinality q(value,ord)),'[]'::jsonb),true)
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v123_status(p_session jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case
   when coalesce(p_session->>'normalStatus','')='confirmed' and coalesce(p_session->>'qrCountStatus','')='confirmed'
     then case when coalesce(p_session->>'isTest','false')='true' then 'test_confirmed' else 'confirmed' end
   when coalesce(p_session->>'normalStatus','')='submitted' and coalesce(p_session->>'qrCountStatus','')='submitted'
     then case when coalesce(p_session->>'isTest','false')='true' then 'test_submitted' else 'submitted' end
   when coalesce(p_session->>'isTest','false')='true' then 'test_counting' else 'counting' end
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v124_prices_complete(p_session jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_section text;v_line jsonb;v_actual numeric;v_price numeric;
begin
 for v_section in select unnest(case when p_session->>'room'='room2' then array['normal','qr','kataoka'] else array['normal','qr'] end) loop
  if (case v_section when 'normal' then p_session->>'normalStatus' when 'qr' then p_session->>'qrCountStatus' else p_session->>'kataokaStatus' end)<>'confirmed' then return false;end if;
  for v_line in select value from jsonb_array_elements(public.seika_inventory_count_v124_section_rows(p_session,v_section)) loop
   v_actual:=public.seika_inventory_count_decimal_optional_v123(v_line->>'actualQty','実数');if v_actual is null then return false;end if;if v_actual<>0 then v_price:=public.seika_inventory_count_decimal_optional_v123(v_line->>'unitPriceYenPerKg','単価');if v_price is null or v_price<0 then return false;end if;end if;
  end loop;
 end loop;return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v124_section_rows(p_session jsonb, p_section text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case p_section when 'normal' then coalesce(p_session->'lines','[]'::jsonb) when 'qr' then coalesce(p_session->'qrLines','[]'::jsonb) when 'kataoka' then coalesce(p_session->'kataokaLines','[]'::jsonb) else '[]'::jsonb end
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v124_status(p_session jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case
   when coalesce(p_session->>'room','')='room2'
    and coalesce(p_session->>'normalStatus','')='confirmed'
    and coalesce(p_session->>'qrCountStatus','')='confirmed'
    and coalesce(p_session->>'kataokaStatus','')='confirmed'
    then case when coalesce(p_session->>'isTest','false')='true' then 'test_confirmed' else 'confirmed' end
   when coalesce(p_session->>'room','')<>'room2'
    and coalesce(p_session->>'normalStatus','')='confirmed'
    and coalesce(p_session->>'qrCountStatus','')='confirmed'
    then case when coalesce(p_session->>'isTest','false')='true' then 'test_confirmed' else 'confirmed' end
   when coalesce(p_session->>'normalStatus','') in ('submitted','confirmed')
    and coalesce(p_session->>'qrCountStatus','') in ('submitted','confirmed')
    and (coalesce(p_session->>'room','')<>'room2' or coalesce(p_session->>'kataokaStatus','') in ('submitted','confirmed'))
    then case when coalesce(p_session->>'isTest','false')='true' then 'test_submitted' else 'submitted' end
   else case when coalesce(p_session->>'isTest','false')='true' then 'test_counting' else 'counting' end
 end
$function$
;
CREATE OR REPLACE FUNCTION public.seika_inventory_count_v124_trim_operations(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(value order by ord),'[]'::jsonb)
 from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) with ordinality q(value,ord)
 where ord>greatest(jsonb_array_length(coalesce(p_rows,'[]'::jsonb))-50,0)
$function$
;
CREATE OR REPLACE FUNCTION public.seika_item_name_group_v1200(p_name text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with g(names) as (
    values
    (array['人参','人参（国産）','国産人参']),
    (array['葉付き大根','葉付大根']),
    (array['玉葱','玉ねぎ']),
    (array['グリーンリーフ','グリーンカール','リーフレタス','リーフ']),
    (array['サニーレタス','サニー']),
    (array['ロメインレタス','ロメイン'])
  ),
  hit as (
    select names from g where btrim(coalesce(p_name,'')) = any(names) limit 1
  )
  select coalesce(
    (select names from hit),
    array[btrim(coalesce(p_name,''))]
  );
$function$
;
CREATE OR REPLACE FUNCTION public.seika_mark_password_changed_v1202()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    declare
      v_rows integer;
    begin
      if auth.uid() is null then
        return jsonb_build_object('ok', false, 'message', 'AUTH_REQUIRED');
      end if;

      update public.profiles
         set must_change_password = false
       where id = auth.uid();

      get diagnostics v_rows = row_count;
      return jsonb_build_object('ok', v_rows > 0, 'updated', v_rows);
    end;
    $function$
;
CREATE OR REPLACE FUNCTION public.seika_parse_kg_v1162(p_value text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_text text;
begin
  v_text:=lower(btrim(translate(coalesce(p_value,''),'０１２３４５６７８９．，ｋｇ','0123456789.,kg')));
  v_text:=regexp_replace(v_text,'[[:space:]]*(kg|㎏|キロ)$','','i');
  v_text:=btrim(v_text);
  if v_text!~'^[+]?[0-9]+([.][0-9]+)?$' then return null; end if;
  return v_text::numeric;
exception when others then
  return null;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_permission_diagnostics_v1145()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_role text;
begin
  v_profile := public.seika_current_profile_v1145();
  v_role := lower(btrim(v_profile.role::text));

  return jsonb_build_object(
    'ok', true,
    'auth_uid', auth.uid(),
    'profile_id', v_profile.id,
    'ids_match', v_profile.id = auth.uid(),
    'legacy_user_id', v_profile.legacy_user_id,
    'display_name', v_profile.display_name,
    'role', v_role,
    'active', v_profile.active,
    'monthly_permissions', jsonb_build_object(
      'waste', public.seika_archive_module_allowed_v1101('waste', v_role),
      'qr', public.seika_archive_module_allowed_v1101('qr', v_role),
      'trimming', public.seika_archive_module_allowed_v1101('trimming', v_role),
      'quality', public.seika_archive_module_allowed_v1101('quality', v_role)
    )
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_purge_old_inventory_counts_v1205(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_keep jsonb;
  v_deleted jsonb;
  v_count int;
  v_version bigint;
begin
  if p_id <> 'ishioka_inventory_production_v2' then
    raise exception '対象が不正です' using errcode = '22023';
  end if;
  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role <> 'admin' then
    raise exception '棚卸しの削除は管理者のみです' using errcode = '42501';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;

  with s as (
    select x.e, x.ord,
           case
             when x.e->>'monthEndMode' = 'month_end_v188' then nullif(x.e->>'v188ConfirmedAt','')
             when coalesce(x.e->>'status','') in ('completed','confirmed','test_confirmed','reversed','cancelled')
               then coalesce(nullif(x.e->>'v177CompletedAt',''), nullif(x.e->>'v177AppliedAt',''),
                             nullif(x.e->>'v186ConfirmedAt',''), nullif(x.e->>'confirmedAt',''),
                             nullif(x.e->>'updatedAt',''), nullif(x.e->>'startedAt',''))
             else null
           end as closed_text
      from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) with ordinality x(e, ord)
  ), j as (
    select e, ord,
           closed_text ~ '^\d{4}-\d{2}-\d{2}'
           and (closed_text::timestamptz + interval '3 months') <= pg_catalog.now() as expired
      from s
  )
  select coalesce(jsonb_agg(e order by ord) filter (where not coalesce(expired,false)), '[]'::jsonb),
         coalesce(jsonb_agg(e order by ord) filter (where coalesce(expired,false)), '[]'::jsonb)
    into v_keep, v_deleted
    from j;

  v_count := jsonb_array_length(v_deleted);
  if v_count = 0 then
    return jsonb_build_object('ok', true, 'deleted', 0);
  end if;

  insert into public.seika_inventory_counts_backup_v1205 (reason, session)
  select '3か月経過で削除', e from jsonb_array_elements(v_deleted) e;

  update public.app_state
     set data = jsonb_set(data, '{inventoryCounts,sessions}', v_keep),
         version = version + 1,
         updated_at = pg_catalog.now()
   where id = v_state.id
   returning version into v_version;

  return jsonb_build_object('ok', true, 'deleted', v_count, 'version', v_version,
    'countNos', (select jsonb_agg(e->>'countNo') from jsonb_array_elements(v_deleted) e));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_qr_block_lot_hard_delete_v1119()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception 'QRロットの物理削除は禁止です。誤登録は安全な論理削除RPCを使用してください' using errcode='42501';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_qr_guard_lot_soft_delete_v1119()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.active is distinct from new.active and coalesce(current_setting('app.seika_qr_lot_delete_v1119',true),'')<>'authorized' then
    raise exception 'QRロットの有効状態を直接変更することはできません' using errcode='42501';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_qr_guard_quality_invalidation_v1119()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.active is distinct from new.active and coalesce(current_setting('app.seika_qr_lot_delete_v1119',true),'')<>'authorized' then
    raise exception '品質評価の有効状態を直接変更することはできません' using errcode='42501';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_qr_guard_quality_photo_invalidation_v1119()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.active is distinct from new.active and coalesce(current_setting('app.seika_qr_lot_delete_v1119',true),'')<>'authorized' then
    raise exception '品質写真の有効状態を直接変更することはできません' using errcode='42501';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_qr_operation_cancelled_v1162(p_operation_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select nullif(btrim(coalesce(p_operation_id,'')),'') is not null and exists(
    select 1
    from public.qr_lot_movements c
    where c.reversed_operation_id::text=p_operation_id
       or coalesce(c.operation_meta->>'originalOperationId','')=p_operation_id
       or coalesce(c.operation_meta->>'original_operation_id','')=p_operation_id
       or coalesce(c.operation_meta->>'cancelOf','')=p_operation_id
       or coalesce(c.operation_meta->>'cancel_of','')=p_operation_id
  );
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_archive_after_photo_finalize_v1102()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_month date;
begin
  if old.upload_status <> 'finalized' and new.upload_status = 'finalized' then
    select public.seika_quality_month_v1102(e.evaluated_at) into v_month
    from public.qr_quality_evaluations e where e.id=new.evaluation_id;
    perform public.seika_quality_archive_invalidate_v1102(v_month);
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_archive_before_insert_v1102()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.seika_quality_archive_invalidate_v1102(public.seika_quality_month_v1102(new.evaluated_at));
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_archive_invalidate_v1102(p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform pg_advisory_xact_lock(hashtextextended('quality:' || p_month::text, 1102));
  if exists (
    select 1 from public.seika_monthly_archives
    where module='quality' and target_month=p_month and status in ('deleting','deleted')
  ) then
    raise exception '整理中または整理済みの月には品質評価を追加できません';
  end if;
  update public.seika_monthly_archives
  set status='pending', file_name=null, row_count=0, photo_count=0,
      excel_created_at=null, excel_created_by=null, excel_created_by_name=null,
      excel_saved_at=null, excel_saved_by=null, excel_saved_by_name=null, updated_at=now()
  where module='quality' and target_month=p_month and status in ('excel_created','excel_saved');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_buyer_context_for_item_v1144(p_lot_id uuid, p_item_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lot public.qr_lots%rowtype;
  v_profile public.profiles%rowtype;
  v_direct jsonb;
  v_fallback jsonb;
  v_item_name text;
  v_master_legacy_user_id text;
begin
  if p_lot_id is not null then
    select * into v_lot from public.qr_lots where id = p_lot_id;
  end if;
  v_item_name := coalesce(v_lot.item_name, p_item_name);

  -- 1. 入庫時に明示保存されたprofile → legacy ID → 一意表示名
  v_profile := null;
  if v_lot.id is not null and v_lot.purchase_staff_profile_id is not null then
    select p.* into v_profile
    from public.profiles p
    where p.id = v_lot.purchase_staff_profile_id and p.active = true;
  end if;
  if v_profile.id is null and v_lot.id is not null and nullif(btrim(coalesce(v_lot.purchase_staff_legacy_user_id, '')), '') is not null then
    select p.* into v_profile
    from public.seika_v1144_profile_by_legacy_user_id(v_lot.purchase_staff_legacy_user_id) p;
  end if;
  if v_profile.id is null and v_lot.id is not null and nullif(btrim(coalesce(v_lot.purchase_staff, '')), '') is not null then
    select pr.* into v_profile
    from public.profiles pr
    join public.seika_v1144_profile_for_purchase_staff_name(v_lot.purchase_staff) p on p.profile_id = pr.id;
  end if;
  if v_profile.id is not null then
    v_direct := jsonb_build_array(jsonb_build_object(
      'profile_id', v_profile.id, 'legacy_user_id', v_profile.legacy_user_id,
      'display_name', v_profile.display_name, 'can_acknowledge', v_profile.role = 'buyer'
    ));
    return jsonb_build_object(
      'buyers', v_direct,
      'acknowledger_legacy_user_ids', case when v_profile.role = 'buyer' then jsonb_build_array(v_profile.legacy_user_id) else '[]'::jsonb end,
      'buyer_source', case when v_lot.purchase_staff_profile_id is not null or nullif(btrim(coalesce(v_lot.purchase_staff_legacy_user_id, '')), '') is not null then 'receipt' else 'legacy_receipt_name' end
    );
  end if;

  -- 2. 添付担当表の固定品名マスタ。activeなbuyer profileが一意の場合だけ表示・確認権限を付与します。
  v_master_legacy_user_id := public.seika_v1144_item_name_master_legacy_user_id(v_item_name);
  if v_master_legacy_user_id is not null then
    v_profile := null;
    select p.* into v_profile
    from public.profiles p
    where p.active = true and p.role = 'buyer' and p.legacy_user_id = v_master_legacy_user_id
      and 1 = (select count(*) from public.profiles p2 where p2.active = true and p2.role = 'buyer' and p2.legacy_user_id = v_master_legacy_user_id);
    if v_profile.id is not null then
      v_direct := jsonb_build_array(jsonb_build_object(
        'profile_id', v_profile.id, 'legacy_user_id', v_profile.legacy_user_id,
        'display_name', v_profile.display_name, 'can_acknowledge', true
      ));
      return jsonb_build_object(
        'buyers', v_direct, 'acknowledger_legacy_user_ids', jsonb_build_array(v_profile.legacy_user_id),
        'buyer_source', 'item_name_master'
      );
    end if;
    -- 固定マスタ対象だがprofileが不正な場合、別担当への誤振分けを防ぐため未設定とします。
    return jsonb_build_object('buyers', '[]'::jsonb, 'acknowledger_legacy_user_ids', '[]'::jsonb, 'buyer_source', null);
  end if;

  -- 3. 従来のapp_state.buyerAssignments。固定マスタにない品目だけで互換維持します。
  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id', p.id, 'legacy_user_id', b.legacy_user_id, 'display_name', b.display_name, 'can_acknowledge', true
  ) order by b.legacy_user_id), '[]'::jsonb)
  into v_fallback
  from public.seika_quality_buyers_for_item_v1103(coalesce(v_lot.item_id::text, '')) b
  join public.profiles p on p.legacy_user_id = b.legacy_user_id and p.active = true and p.role = 'buyer';

  return jsonb_build_object(
    'buyers', v_fallback,
    'acknowledger_legacy_user_ids', coalesce((select jsonb_agg(x ->> 'legacy_user_id') from jsonb_array_elements(v_fallback) x), '[]'::jsonb),
    'buyer_source', case when jsonb_array_length(v_fallback) > 0 then 'item_assignment' else null end
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_buyer_context_for_lot_v1144(p_lot_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.seika_quality_buyer_context_for_item_v1144(p_lot_id, null)
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_buyer_context_for_lot_v1159(p_lot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lot public.qr_lots%rowtype;
  v_profile public.profiles%rowtype;
  v_count integer;
  v_name text;
  v_legacy_id text;
  v_display_name text;
  v_buyers jsonb;
begin
  select * into v_lot
  from public.qr_lots
  where id = p_lot_id;

  if not found then
    return jsonb_build_object(
      'buyers','[]'::jsonb,
      'acknowledger_profile_ids','[]'::jsonb,
      'buyer_source',null
    );
  end if;

  if v_lot.purchase_staff_profile_id is not null then
    select p.* into v_profile
    from public.profiles p
    where p.id = v_lot.purchase_staff_profile_id
      and p.active = true;
  end if;

  if v_profile.id is null
     and nullif(btrim(coalesce(v_lot.purchase_staff_legacy_user_id,'')),'') is not null then
    v_legacy_id := case btrim(v_lot.purchase_staff_legacy_user_id)
      when 'saito' then 'saito_dai'
      when 'seki' then 'seki_hiroshi'
      else btrim(v_lot.purchase_staff_legacy_user_id)
    end;

    select count(*) into v_count
    from public.profiles p
    where p.active = true
      and p.legacy_user_id = v_legacy_id;

    if v_count = 1 then
      select p.* into v_profile
      from public.profiles p
      where p.active = true
        and p.legacy_user_id = v_legacy_id
      limit 1;
    else
      v_profile := null;
    end if;
  end if;

  if v_profile.id is null
     and nullif(btrim(coalesce(v_lot.purchase_staff,'')),'') is not null then
    v_name := regexp_replace(
      replace(replace(btrim(v_lot.purchase_staff),'（','('),'）',')'),
      '[[:space:]]','','g'
    );
    v_legacy_id := case v_name
      when '斎藤(大)' then 'saito_dai'
      when '斎藤大明' then 'saito_dai'
      when '関(宏)' then 'seki_hiroshi'
      when '関宏世' then 'seki_hiroshi'
      when '坂本' then 'sakamoto'
      when '坂本美穂' then 'sakamoto'
      when '吉田' then 'yoshida'
      when '吉田智彦' then 'yoshida'
      when '荒木' then 'araki'
      when '荒木貴裕' then 'araki'
      else null
    end;

    if v_legacy_id is not null then
      select count(*) into v_count
      from public.profiles p
      where p.active = true
        and p.legacy_user_id = v_legacy_id;

      if v_count = 1 then
        select p.* into v_profile
        from public.profiles p
        where p.active = true
          and p.legacy_user_id = v_legacy_id
        limit 1;
      else
        v_profile := null;
      end if;
    else
      select count(*) into v_count
      from public.profiles p
      where p.active = true
        and regexp_replace(
          replace(replace(btrim(coalesce(p.display_name,'')),'（','('),'）',')'),
          '[[:space:]]','','g'
        ) = v_name;

      if v_count = 1 then
        select p.* into v_profile
        from public.profiles p
        where p.active = true
          and regexp_replace(
            replace(replace(btrim(coalesce(p.display_name,'')),'（','('),'）',')'),
            '[[:space:]]','','g'
          ) = v_name
        limit 1;
      else
        v_profile := null;
      end if;
    end if;
  end if;

  if v_profile.id is not null then
    v_display_name := case v_profile.legacy_user_id
      when 'saito_dai' then '斎藤 大明'
      when 'seki_hiroshi' then '関 宏世'
      when 'sakamoto' then '坂本 美穂'
      when 'yoshida' then '吉田 智彦'
      when 'araki' then '荒木 貴裕'
      else v_profile.display_name
    end;
    return jsonb_build_object(
      'buyers',jsonb_build_array(jsonb_build_object(
        'profile_id',v_profile.id,
        'legacy_user_id',v_profile.legacy_user_id,
        'display_name',v_display_name,
        'can_acknowledge',v_profile.role='buyer'
      )),
      'acknowledger_profile_ids',
        case when v_profile.role='buyer'
          then jsonb_build_array(v_profile.id)
          else '[]'::jsonb
        end,
      'buyer_source','receipt'
    );
  end if;

  if nullif(btrim(coalesce(v_lot.purchase_staff,'')),'') is not null then
    v_name := regexp_replace(
      replace(replace(btrim(v_lot.purchase_staff),'（','('),'）',')'),
      '[[:space:]]','','g'
    );
    v_legacy_id := case v_name
      when '斎藤(大)' then 'saito_dai'
      when '斎藤大明' then 'saito_dai'
      when '関(宏)' then 'seki_hiroshi'
      when '関宏世' then 'seki_hiroshi'
      when '坂本' then 'sakamoto'
      when '坂本美穂' then 'sakamoto'
      when '吉田' then 'yoshida'
      when '吉田智彦' then 'yoshida'
      when '荒木' then 'araki'
      when '荒木貴裕' then 'araki'
      else null
    end;
    v_display_name := case v_legacy_id
      when 'saito_dai' then '斎藤 大明'
      when 'seki_hiroshi' then '関 宏世'
      when 'sakamoto' then '坂本 美穂'
      when 'yoshida' then '吉田 智彦'
      when 'araki' then '荒木 貴裕'
      else btrim(v_lot.purchase_staff)
    end;
    return jsonb_build_object(
      'buyers',jsonb_build_array(jsonb_build_object(
        'profile_id',null,
        'legacy_user_id',v_legacy_id,
        'display_name',v_display_name,
        'can_acknowledge',false
      )),
      'acknowledger_profile_ids','[]'::jsonb,
      'buyer_source','receipt_name_unresolved'
    );
  end if;

  select coalesce(
    jsonb_agg(jsonb_build_object(
      'profile_id',p.id,
      'legacy_user_id',b.legacy_user_id,
      'display_name',case b.legacy_user_id
        when 'saito_dai' then '斎藤 大明'
        when 'seki_hiroshi' then '関 宏世'
        when 'sakamoto' then '坂本 美穂'
        when 'yoshida' then '吉田 智彦'
        when 'araki' then '荒木 貴裕'
        else b.display_name
      end,
      'can_acknowledge',true
    ) order by b.legacy_user_id),
    '[]'::jsonb
  ) into v_buyers
  from public.seika_quality_buyers_for_item_v1103(v_lot.item_id::text) b
  left join public.profiles p
    on p.active = true
   and p.legacy_user_id = b.legacy_user_id;

  return jsonb_build_object(
    'buyers',v_buyers,
    'acknowledger_profile_ids',coalesce((
      select jsonb_agg(x->'profile_id')
      from jsonb_array_elements(v_buyers) x
      where x->>'profile_id' is not null
    ),'[]'::jsonb),
    'buyer_source',case
      when jsonb_array_length(v_buyers)>0 then 'item_assignment'
      else null
    end
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_buyers_for_item_v1103(p_item_id text)
 RETURNS TABLE(legacy_user_id text, display_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with normalized_assignments as (
    select distinct
      case lower(btrim(a.key))
        when 'saito' then 'saito_dai'
        when 'seki' then 'seki_hiroshi'
        else btrim(a.key)
      end as legacy_user_id
    from public.app_state s
    cross join lateral jsonb_each(coalesce(s.data -> 'buyerAssignments', '{}'::jsonb)) as a(key, value)
    where s.id = 'ishioka_inventory_production_v2'
      and jsonb_typeof(a.value) = 'array'
      and exists (
        select 1
        from jsonb_array_elements_text(a.value) as assigned_item(item_id)
        where assigned_item.item_id = p_item_id
      )
  )
  select a.legacy_user_id,
         coalesce(p.display_name, a.legacy_user_id) as display_name
  from normalized_assignments a
  left join lateral (
    select pr.display_name
    from public.profiles pr
    where pr.legacy_user_id = a.legacy_user_id
      and pr.active = true
    order by pr.updated_at desc nulls last, pr.id
    limit 1
  ) p on true
  where a.legacy_user_id <> ''
  order by a.legacy_user_id
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_can_operate_v1102()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
begin
  begin
    v_profile := public.seika_current_profile_v1145();
  exception
    when insufficient_privilege then
      return false;
  end;

  return lower(btrim(v_profile.role::text)) = any(array['admin','worker']);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_month_v1102(p_at timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ select date_trunc('month', p_at at time zone 'Asia/Tokyo')::date $function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_monthly_storage_delete_allowed_v1102(p_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
      declare
        v_profile public.profiles%rowtype;
      begin
        begin
          v_profile := public.seika_current_profile_v1145();
        exception
          when insufficient_privilege then
            return false;
        end;

        if lower(btrim(v_profile.role::text)) <> 'admin' then
          return false;
        end if;

        return exists (
          select 1
          from public.qr_quality_photos p
          join public.qr_quality_evaluations e on e.id = p.evaluation_id
          join public.seika_monthly_archives a
            on a.module = 'quality'
           and a.target_month = date_trunc(
             'month', e.evaluated_at at time zone 'Asia/Tokyo'
           )::date
          where p.storage_path = p_path
            and a.status = 'deleting'
            and a.excel_saved_at is not null
            and a.target_month < (
              date_trunc('month', now() at time zone 'Asia/Tokyo') - interval '3 months'
            )::date
        );
      end;
      $function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_monthly_storage_delete_allowed_v1166(p_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
begin
  select * into v_profile from public.seika_archive_profile_v1101();
  if not found or v_profile.role <> 'admin' then
    return false;
  end if;

  return exists (
    select 1
    from public.qr_quality_photos p
    join public.qr_quality_evaluations e on e.id = p.evaluation_id
    join public.seika_monthly_archives a
      on a.module = 'quality'
     and a.target_month = public.seika_quality_month_v1102(e.evaluated_at)
    where p.storage_path = p_path
      and a.status = 'deleting'
      and a.excel_saved_at is not null
      and a.target_month < (date_trunc('month', now() at time zone 'Asia/Tokyo') - interval '3 months')::date
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_profile_v1102()
 RETURNS profiles
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.seika_current_profile_v1145()
$function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_push_my_profile_v1144()
 RETURNS profiles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
      declare
        v_profile public.profiles%rowtype;
      begin
        v_profile := public.seika_current_profile_v1145();
        if lower(btrim(v_profile.role::text)) <> 'buyer' then
          raise exception '品質評価通知を設定できるのは有効な仕入れ担当者だけです'
            using errcode = '42501';
        end if;
        return v_profile;
      end;
      $function$
;
CREATE OR REPLACE FUNCTION public.seika_quality_upload_path_allowed_v1102(p_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
begin
  begin
    v_profile := public.seika_current_profile_v1145();
  exception
    when insufficient_privilege then
      return false;
  end;

  if lower(btrim(v_profile.role::text)) <> all(array['admin','worker']) then
    return false;
  end if;

  return exists (
    select 1
    from public.qr_quality_photos p
    where p.storage_path = p_path
      and p.upload_status = 'pending'
      and p.uploaded_by = v_profile.id
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_uuid_v188(p_value text)
 RETURNS uuid
 LANGUAGE plpgsql
 IMMUTABLE STRICT
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v text := lower(trim(p_value));
  h text;
begin
  if v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return v::uuid;
  end if;
  h := md5(p_value);
  return (substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-a'||substr(h,18,3)||'-'||substr(h,21,12))::uuid;
end
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1136_active_profile()
 RETURNS profiles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype; begin select * into v from public.profiles where id=auth.uid() and active limit 1; if not found then raise exception '有効なログイン利用者ではありません' using errcode='42501'; end if; return v; end $function$
;
CREATE OR REPLACE FUNCTION public.seika_v1136_get_fifo_mode()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (select mode from public.seika_feature_modes_v1136 where feature_key='smart_fifo') $function$
;
CREATE OR REPLACE FUNCTION public.seika_v1136_require_roles(p_roles text[])
 RETURNS profiles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype; begin v:=public.seika_v1136_active_profile(); if coalesce(array_length(p_roles,1),0)=0 or not (v.role=any(p_roles)) then raise exception 'この機能を実行する権限がありません' using errcode='42501'; end if; return v; end $function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_fill_purchase_staff_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype; v_name text; v_count integer;
begin
  v_name:=btrim(coalesce(new.purchase_staff,''));
  v_name:=replace(replace(v_name,'斎藤（大）','斎藤 大明'),'斎藤(大)','斎藤 大明');
  v_name:=replace(replace(v_name,'関（宏）','関 宏世'),'関(宏)','関 宏世');
  if v_name='' then raise exception '仕入れ担当者を入力してください' using errcode='22023'; end if;
  if char_length(v_name)>80 or v_name ~ '[[:cntrl:]]' then
    raise exception '仕入れ担当者は1〜80文字で入力してください' using errcode='22023';
  end if;
  v_profile:=null;
  if new.purchase_staff_profile_id is not null then
    select p.* into v_profile from public.profiles p where p.id=new.purchase_staff_profile_id and p.active=true;
  end if;
  if v_profile.id is null and nullif(btrim(coalesce(new.purchase_staff_legacy_user_id,'')),'') is not null then
    select p.* into v_profile from public.seika_v1144_profile_by_legacy_user_id(new.purchase_staff_legacy_user_id) p;
  end if;
  if v_profile.id is null then
    select count(*) into v_count from public.profiles p
      where p.active=true and regexp_replace(replace(replace(btrim(p.display_name),'（','('),'）',')'),'\s+','','g')=
        regexp_replace(replace(replace(v_name,'（','('),'）',')'),'\s+','','g');
    if v_count=1 then
      select p.* into v_profile from public.profiles p
        where p.active=true and regexp_replace(replace(replace(btrim(p.display_name),'（','('),'）',')'),'\s+','','g')=
          regexp_replace(replace(replace(v_name,'（','('),'）',')'),'\s+','','g');
    end if;
  end if;
  if v_profile.id is not null then
    new.purchase_staff:=v_profile.display_name;
    new.purchase_staff_profile_id:=v_profile.id;
    new.purchase_staff_legacy_user_id:=v_profile.legacy_user_id;
  else
    new.purchase_staff:=v_name;
    new.purchase_staff_profile_id:=null;
    new.purchase_staff_legacy_user_id:=null;
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_item_name_master_legacy_user_id(p_item_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
  with aliases(legacy_user_id, item_name) as (
    values
      -- 坂本（従来互換：大葉・小葱を含む）
      ('sakamoto','小蕪'), ('sakamoto','小かぶ'), ('sakamoto','こかぶ'), ('sakamoto','水菜'),
      ('sakamoto','小松菜'), ('sakamoto','ほうれん草'), ('sakamoto','ズッキーニ'),
      ('sakamoto','大葉'), ('sakamoto','小葱'),
      -- 斎藤（大）
      ('saito_dai','ニラ'), ('saito_dai','青梗菜'), ('saito_dai','茄子'), ('saito_dai','長茄子'),
      ('saito_dai','ゴーヤ'), ('saito_dai','ゴーヤー'), ('saito_dai','ピーマン'),
      ('saito_dai','胡瓜'), ('saito_dai','きゅうり'), ('saito_dai','キュウリ'),
      ('saito_dai','トマト'), ('saito_dai','ミニトマト'), ('saito_dai','南瓜'),
      ('saito_dai','キャベツ'), ('saito_dai','紫キャベツ'), ('saito_dai','長葱'),
      ('saito_dai','大根'), ('saito_dai','カット大根'), ('saito_dai','葉付き大根'), ('saito_dai','葉付大根'),
      ('saito_dai','蓮根'), ('saito_dai','レンコン'), ('saito_dai','れんこん'),
      -- 荒木
      ('araki','国産人参'), ('araki','人参（国産）'), ('araki','人参'),
      -- 吉田
      ('yoshida','レタス'), ('yoshida','グリーンカール'), ('yoshida','サニーレタス'), ('yoshida','サニー'),
      ('yoshida','リーフレタス'), ('yoshida','リーフ'), ('yoshida','ロメインレタス'), ('yoshida','ロメイン'), ('yoshida','白菜'),
      -- 関（宏）（従来互換：じゃが芋系を含む）
      ('seki_hiroshi','さつま芋'), ('seki_hiroshi','さつまいも'), ('seki_hiroshi','玉葱'), ('seki_hiroshi','玉ねぎ'), ('seki_hiroshi','紫玉葱'),
      ('seki_hiroshi','じゃが芋'), ('seki_hiroshi','ジャガイモ'), ('seki_hiroshi','馬鈴薯'),
      ('seki_hiroshi','男爵じゃが芋'), ('seki_hiroshi','メークインじゃが芋'), ('seki_hiroshi','きたあかりじゃが芋'),
      ('seki_hiroshi','北あかりじゃが芋'), ('seki_hiroshi','とうや'), ('seki_hiroshi','インカのめざめ'), ('seki_hiroshi','北海黄金')
  )
  select a.legacy_user_id
  from aliases a
  where public.seika_v1144_normalize_item_name(a.item_name)
      = public.seika_v1144_normalize_item_name(p_item_name)
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_normalize_item_name(p_item_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO ''
AS $function$
  select nullif(
    translate(
      btrim(p_item_name),
      '　０１２３４５６７８９ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ（） ',
      ' 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz()'
    ),
    ''
  )
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_profile_by_legacy_user_id(p_legacy_user_id text)
 RETURNS profiles
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p
  from public.profiles p
  where p.active = true
    and p.legacy_user_id = nullif(btrim(coalesce(p_legacy_user_id, '')), '')
    and 1 = (
      select count(*)
      from public.profiles p2
      where p2.active = true
        and p2.legacy_user_id = nullif(btrim(coalesce(p_legacy_user_id, '')), '')
    )
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_profile_for_purchase_staff_name(p_display_name text)
 RETURNS TABLE(profile_id uuid, legacy_user_id text, display_name text, role text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with normalized as (
    select nullif(regexp_replace(replace(replace(btrim(coalesce(p_display_name, '')), '（', '('), '）', ')'), '\s+', '', 'g'), '') as name
  ), candidates as (
    select p.id, p.legacy_user_id, p.display_name, p.role,
      count(*) filter (where p.role = 'buyer') over () as buyer_count,
      count(*) over () as all_count
    from public.profiles p
    cross join normalized n
    where p.active = true
      and nullif(regexp_replace(replace(replace(btrim(coalesce(p.display_name, '')), '（', '('), '）', ')'), '\s+', '', 'g'), '') = n.name
  )
  select id, legacy_user_id, display_name, role
  from candidates
  where (buyer_count = 1 and role = 'buyer')
     or (buyer_count = 0 and all_count = 1)
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_qr_operation_cancelled(p_operation_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select nullif(btrim(coalesce(p_operation_id,'')),'') is not null and exists(
    select 1 from public.qr_lot_movements c
    where c.reversed_operation_id::text=p_operation_id
       or coalesce(c.operation_meta->>'originalOperationId','')=p_operation_id
       or coalesce(c.operation_meta->>'original_operation_id','')=p_operation_id
       or coalesce(c.operation_meta->>'cancelOf','')=p_operation_id
       or coalesce(c.operation_meta->>'cancel_of','')=p_operation_id
  );
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_qr_operation_cancelled(p_operation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_operation_id is not null and exists(
    select 1
    from public.qr_lot_movements c
    where c.reversed_operation_id::text=p_operation_id::text
       or coalesce(c.operation_meta->>'originalOperationId','')=p_operation_id::text
       or coalesce(c.operation_meta->>'original_operation_id','')=p_operation_id::text
       or coalesce(c.operation_meta->>'cancelOf','')=p_operation_id::text
       or coalesce(c.operation_meta->>'cancel_of','')=p_operation_id::text
  );
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_require_active_profile()
 RETURNS profiles
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.seika_current_profile_v1145()
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1144_resolve_quality_lot(p_lot_id text, p_qr_key text)
 RETURNS TABLE(lot_id uuid, qr_key text, item_id text, item_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with candidates as (
    select q.id as lot_id,
           q.qr_key,
           q.item_id::text as item_id,
           q.item_name,
           q.created_at,
           0 as priority
    from public.qr_lots q
    where nullif(btrim(coalesce(p_lot_id, '')), '') is not null
      and q.id::text = btrim(p_lot_id)
      and q.qr_key = btrim(coalesce(p_qr_key, ''))
      and q.active = true

    union all

    select q.id as lot_id,
           q.qr_key,
           q.item_id::text as item_id,
           q.item_name,
           q.created_at,
           1 as priority
    from public.qr_lots q
    where q.qr_key = btrim(coalesce(p_qr_key, ''))
      and q.active = true
  )
  select c.lot_id, c.qr_key, c.item_id, c.item_name
  from candidates c
  order by c.priority, c.created_at desc nulls last, c.lot_id desc
  limit 1
$function$
;
CREATE OR REPLACE FUNCTION public.seika_v1159_qr_operator()
 RETURNS profiles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
begin
  select p.* into v_profile
  from public.profiles p
  where p.id=auth.uid() and p.active=true and p.role in ('admin','worker')
  limit 1;
  if not found then
    raise exception 'QR訂正履歴を保存する権限がありません' using errcode='42501';
  end if;
  return v_profile;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_admin_notice_active_v1150(p_id text, p_expected_version bigint, p_notice_id text, p_active boolean, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor record;
  v_state public.app_state%rowtype;
  v_existing public.seika_admin_notice_operations_v1150%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_request jsonb;
  v_request_hash text;
  v_response jsonb;
  v_version bigint;
begin
  select * into v_actor from public.seika_admin_notice_require_admin_v1150();
  if p_id is null or btrim(p_id) = '' or p_expected_version is null then raise exception '状態IDまたは版番号が不正です' using errcode='22023'; end if;
  if p_notice_id is null or char_length(btrim(p_notice_id)) not between 1 and 200 then raise exception 'お知らせIDが不正です' using errcode='22023'; end if;
  if p_active is null then raise exception '表示状態が不正です' using errcode='22023'; end if;
  if p_operation_id is null or char_length(btrim(p_operation_id)) not between 1 and 200 then raise exception '操作IDが不正です' using errcode='22023'; end if;

  v_request := jsonb_build_object('action','set_active','stateId',p_id,'expectedVersion',p_expected_version,'noticeId',p_notice_id,'active',p_active);
  v_request_hash := encode(extensions.digest(convert_to(v_request::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtext(p_operation_id));
  select * into v_existing from public.seika_admin_notice_operations_v1150 where operation_id=p_operation_id;
  if found then
    if v_existing.actor_id <> v_actor.actor_id or v_existing.request_hash <> v_request_hash then raise exception '同じ操作IDに異なる要求は使用できません' using errcode='22023'; end if;
    return v_existing.response;
  end if;

  select * into v_state from public.app_state where id=p_id for update;
  if not found then raise exception 'アプリ状態が見つかりません' using errcode='P0002'; end if;
  if v_state.version is distinct from p_expected_version then
    v_response:=jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'message','他の端末で更新されています。最新データを取得して再試行してください');
    return v_response;
  end if;

  select jsonb_build_object('id',notice_id,'title',title,'body',body,'startsAt',starts_at,'endsAt',ends_at,'active',active,'createdAt',created_at,'createdBy',created_by,'createdById',created_by_id,'updatedAt',updated_at)
  into v_before from public.seika_admin_notices_v1150 where state_id=p_id and notice_id=btrim(p_notice_id) for update;
  if v_before is null then raise exception 'お知らせが見つかりません' using errcode='P0002'; end if;

  update public.seika_admin_notices_v1150 set active=p_active, updated_at=now() where state_id=p_id and notice_id=btrim(p_notice_id);
  v_version:=public.seika_admin_notice_sync_app_state_v1150(p_id);
  select jsonb_build_object('id',notice_id,'title',title,'body',body,'startsAt',starts_at,'endsAt',ends_at,'active',active,'createdAt',created_at,'createdBy',created_by,'createdById',created_by_id,'updatedAt',updated_at)
  into v_after from public.seika_admin_notices_v1150 where state_id=p_id and notice_id=btrim(p_notice_id);
  v_response:=jsonb_build_object('ok',true,'conflict',false,'version',v_version,'operationId',p_operation_id,'notice',v_after);

  insert into public.seika_admin_notice_audit_v1150(state_id,notice_id,action,operation_id,actor_id,actor_role,request_hash,before_notice,after_notice,expected_version,resulting_version)
  values(p_id,btrim(p_notice_id),'set_active',p_operation_id,v_actor.actor_id,v_actor.actor_role,v_request_hash,v_before,v_after,p_expected_version,v_version);
  insert into public.seika_admin_notice_operations_v1150(operation_id,actor_id,action,request_hash,response) values(p_operation_id,v_actor.actor_id,'set_active',v_request_hash,v_response);
  return v_response;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_fifo_lot_hold_v1136(p_lot_id uuid, p_hold boolean, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;l public.qr_lots%rowtype;begin v:=public.trimming_require_role(array['admin']);if p_lot_id is null or char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'lot_idと理由（1〜500文字）が必要です';end if;select * into l from public.qr_lots where id=p_lot_id for update;if not found then raise exception 'QRロットが見つかりません';end if;if p_hold then insert into public.seika_fifo_lot_holds_v1136(lot_id,active,hold_reason,held_at,held_by,updated_at)values(p_lot_id,true,btrim(p_reason),now(),v.id,now())on conflict(lot_id)do update set active=true,hold_reason=excluded.hold_reason,held_at=excluded.held_at,held_by=excluded.held_by,released_at=null,released_by=null,updated_at=excluded.updated_at;insert into public.seika_fifo_hold_override_audit_v1136(actor_id,event_kind,lot_id,reason,detail)values(v.id,'hold',p_lot_id,btrim(p_reason),jsonb_build_object('qr_key',l.qr_key));else update public.seika_fifo_lot_holds_v1136 set active=false,released_at=now(),released_by=v.id,updated_at=now()where lot_id=p_lot_id and active;if not found then raise exception '有効な保留がありません';end if;insert into public.seika_fifo_hold_override_audit_v1136(actor_id,event_kind,lot_id,reason,detail)values(v.id,'release',p_lot_id,btrim(p_reason),jsonb_build_object('qr_key',l.qr_key));end if;return jsonb_build_object('ok',true,'lot_id',p_lot_id,'held',p_hold);end $function$
;
CREATE OR REPLACE FUNCTION public.set_seika_feature_mode_v1136(p_mode text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype; b jsonb; a jsonb; begin
 v:=public.trimming_require_role(array['admin']);
 if p_mode not in ('disabled','shadow') then raise exception 'warn/enforceへの移行は申請・承認RPCを使用してください'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception '変更理由は1〜500文字で入力してください'; end if;
 select to_jsonb(x) into b from public.seika_feature_modes_v1136 x where feature_key='smart_fifo' for update;
 update public.seika_feature_modes_v1136 set mode=p_mode,updated_at=now(),updated_by=v.id,update_reason=btrim(p_reason) where feature_key='smart_fifo' returning to_jsonb(seika_feature_modes_v1136.*) into a;
 update public.seika_fifo_mode_transition_approvals_v1136 set status='superseded',decided_at=now(),decided_by=v.id,decision_reason='通常モード変更により未承認申請を無効化: '||btrim(p_reason) where status='pending';
 insert into public.seika_policy_audit_v1136(audited_by,audit_kind,subject_key,action,before_state,after_state,reason) values(v.id,'feature_mode','smart_fifo','mode_change',b,a,btrim(p_reason));
 return jsonb_build_object('ok',true,'mode',p_mode); end $function$
;
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.soft_delete_mistaken_qr_lot_v1119(p_qr_key text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_qr_key text:=btrim(coalesce(p_qr_key,''));
  v_reason text:=btrim(coalesce(p_reason,''));
  v_operation_id uuid:=extensions.gen_random_uuid();
  v_movement_count integer:=0;
  v_trimming_count integer:=0;
  v_count_session_count integer:=0;
  v_received_qty numeric;
  v_current_qty numeric;
  v_total_weight numeric;
  v_current_weight numeric;
  v_is_large boolean:=false;
  v_eval public.qr_quality_evaluations%rowtype;
  v_photo public.qr_quality_photos%rowtype;
  v_eval_count integer:=0;
  v_photo_count integer:=0;
  v_blockers jsonb:='[]'::jsonb;
begin
  -- profiles.active と role をサーバー側で判定し、画面側の判定を信用しません。
  v_profile:=public.trimming_require_role(array['admin']);
  if v_qr_key='' or char_length(v_qr_key)>160 then raise exception 'QRキーが不正です' using errcode='22023'; end if;
  if v_reason='' or char_length(v_reason)>500 then raise exception '誤登録削除理由を1〜500文字で入力してください' using errcode='22023'; end if;

  -- active=true の対象行をロックし、同時に別端末の出庫等が確定しないようにします。
  select * into v_lot from public.qr_lots where qr_key=v_qr_key and active=true for update;
  if not found then raise exception '有効なQRロットが見つかりません。すでに削除済み、またはQRキーが不正です' using errcode='P0002'; end if;

  v_current_qty:=coalesce(v_lot.current_qty,0);
  v_received_qty:=coalesce(v_lot.received_qty,0);
  if abs(v_current_qty-v_received_qty)>0.000001 then
    v_blockers:=v_blockers || jsonb_build_array(jsonb_build_object('type','stock_changed','message','現在数量が入庫数量と一致しません（在庫数量が変動しています）'));
  end if;
  v_is_large:=coalesce(v_lot.container_type,'') in ('網コンテナ','鉄コンテナ','パレテーナ');
  if v_is_large then
    v_current_weight:=v_lot.current_weight;
    v_total_weight:=v_lot.total_weight;
    if (v_current_weight is null) is distinct from (v_total_weight is null)
       or (v_current_weight is not null and abs(v_current_weight-v_total_weight)>0.000001) then
      v_blockers:=v_blockers || jsonb_build_array(jsonb_build_object('type','weight_changed','message','大型容器の現在重量が入庫総重量と一致しません（在庫重量が変動しています）'));
    end if;
  end if;
  select count(*) into v_count_session_count
  from public.app_state a
  cross join lateral jsonb_array_elements(coalesce(a.data->'inventoryCounts'->'sessions','[]'::jsonb)) s
  cross join lateral jsonb_array_elements(coalesce(s->'qrLines','[]'::jsonb)) l
  where a.id='ishioka_inventory_production_v2'
    and s->>'status' in ('counting','submitted','qr_confirmed_pending_normal','normal_reversed_pending_qr')
    and coalesce(s->>'isTest','false')<>'true'
    and coalesce(l->>'qrKey',l->>'qr_key','')=v_lot.qr_key;
  if v_count_session_count>0 then
    v_blockers:=v_blockers || jsonb_build_array(jsonb_build_object('type','inventory_count_in_progress','count',v_count_session_count,'message','進行中の棚卸しにこのQRロットが含まれています'));
  end if;

  -- 入庫記録のみは誤登録削除の対象にできます。入庫以外の履歴は、メタデータ訂正を含め全て後続業務として扱います。
  select count(*) into v_movement_count
  from public.qr_lot_movements m
  where m.qr_key=v_lot.qr_key
    and coalesce(btrim(m.movement_type),'') not in ('入庫','QR入庫','初回入庫');
  if v_movement_count>0 then
    v_blockers:=v_blockers || jsonb_build_array(jsonb_build_object('type','qr_lot_movements','count',v_movement_count,'message','出庫・廃棄・調整・棚卸し・訂正等のQR後続履歴があります'));
  end if;

  -- トリミングはQR操作履歴も作りますが、業務テーブルも明示確認して二重に安全側へ倒します。
  if to_regclass('public.trimming_job_lots') is not null then
    select count(*) into v_trimming_count from public.trimming_job_lots t where t.qr_key=v_lot.qr_key;
    if v_trimming_count>0 then
      v_blockers:=v_blockers || jsonb_build_array(jsonb_build_object('type','trimming_job_lots','count',v_trimming_count,'message','トリミング使用履歴があります'));
    end if;
  end if;

  if jsonb_array_length(v_blockers)>0 then
    return jsonb_build_object('ok',false,'deleted',false,'message','後続業務があるため誤登録ロットとして削除できません','blockers',v_blockers);
  end if;

  -- ここからは同一トランザクション。品質評価は必須でも削除の阻害にせず、写真のStorage実体にも触れません。
  perform set_config('app.seika_qr_lot_delete_v1119','authorized',true);

  for v_photo in
    select ph.* from public.qr_quality_photos ph
    join public.qr_quality_evaluations e on e.id=ph.evaluation_id
    where e.qr_key=v_lot.qr_key and e.active and ph.active
    for update of ph
  loop
    insert into public.qr_lot_delete_audit_events_v1119(deletion_operation_id,qr_key,lot_id,event_type,entity_id,before_data,reason,performed_by,performed_by_name)
    values(v_operation_id,v_lot.qr_key,v_lot.id::text,'quality_photo_invalidated',v_photo.id::text,to_jsonb(v_photo),v_reason,v_profile.id,coalesce(v_profile.display_name,''));
    update public.qr_quality_photos set active=false,invalidated_at=now(),invalidated_by=v_profile.id,invalidated_by_name=coalesce(v_profile.display_name,''),invalidation_reason=v_reason,invalidated_by_lot_delete=true where id=v_photo.id;
    v_photo_count:=v_photo_count+1;
  end loop;

  for v_eval in
    select * from public.qr_quality_evaluations where qr_key=v_lot.qr_key and active for update
  loop
    insert into public.qr_lot_delete_audit_events_v1119(deletion_operation_id,qr_key,lot_id,event_type,entity_id,before_data,reason,performed_by,performed_by_name)
    values(v_operation_id,v_lot.qr_key,v_lot.id::text,'quality_evaluation_invalidated',v_eval.id::text,to_jsonb(v_eval),v_reason,v_profile.id,coalesce(v_profile.display_name,''));
    update public.qr_quality_evaluations set active=false,invalidated_at=now(),invalidated_by=v_profile.id,invalidated_by_name=coalesce(v_profile.display_name,''),invalidation_reason=v_reason,invalidated_by_lot_delete=true where id=v_eval.id;
    v_eval_count:=v_eval_count+1;
  end loop;

  insert into public.qr_lot_delete_audit_events_v1119(deletion_operation_id,qr_key,lot_id,event_type,entity_id,before_data,reason,performed_by,performed_by_name)
  values(v_operation_id,v_lot.qr_key,v_lot.id::text,'lot_soft_deleted',v_lot.id::text,to_jsonb(v_lot),v_reason,v_profile.id,coalesce(v_profile.display_name,''));
  update public.qr_lots set active=false,updated_at=now() where id=v_lot.id;

  return jsonb_build_object('ok',true,'deleted',true,'deletion_operation_id',v_operation_id,'qr_key',v_lot.qr_key,'quality_evaluations_invalidated',v_eval_count,'quality_photos_invalidated',v_photo_count,'storage_objects_deleted',0,'message','QRロットを論理削除しました。品質評価・写真DB行は監査を残して無効化し、写真Storage実体は保持しています。');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.submit_feedback_report_v195(p_category text, p_title text, p_body text, p_screen text DEFAULT NULL::text, p_operation_id uuid DEFAULT gen_random_uuid())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_id uuid;
begin
  select *
  into v_profile
  from public.profiles
  where id = auth.uid()
    and active;

  if not found then
    raise exception '有効なログインが必要です'
      using errcode = '42501';
  end if;

  if p_category not in (
    '不具合',
    '操作質問',
    '改善提案',
    'その他'
  ) then
    raise exception '種類を確認してください';
  end if;

  if char_length(trim(coalesce(p_title, ''))) not between 1 and 100 then
    raise exception '件名は1〜100文字で入力してください';
  end if;

  if char_length(trim(coalesce(p_body, ''))) not between 1 and 2000 then
    raise exception '内容は1〜2000文字で入力してください';
  end if;

  insert into public.seika_feedback_reports (
    operation_id,
    reporter_id,
    reporter_legacy_user_id,
    reporter_name,
    reporter_role,
    category,
    title,
    body,
    screen_name
  )
  values (
    p_operation_id,
    v_profile.id,
    v_profile.legacy_user_id,
    v_profile.display_name,
    v_profile.role,
    p_category,
    trim(p_title),
    trim(p_body),
    left(coalesce(p_screen, ''), 100)
  )
  on conflict (operation_id)
  do update set operation_id = excluded.operation_id
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'id', v_id
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.trimming_is_market_supplier_v1117(p_supplier text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select public.trimming_normalize_supplier_v1117(p_supplier)=any(array[
    '大同','水戸大同','大同水戸大同','中央','水戸中央','中央水戸中央','東一','シティ'
  ])
$function$
;
CREATE OR REPLACE FUNCTION public.trimming_lock_inventory_state()
 RETURNS app_state
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_state public.app_state;
begin
  select * into v_state from public.app_state where id = 'ishioka_inventory_production_v2' for update;
  if found then return v_state; end if;
  select * into v_state from public.app_state where id = 'ishioka_inventory_demo_v6_linecopy_weekly' for update;
  if found then return v_state; end if;
  raise exception '通常在庫app_stateが見つかりません（現行・旧IDともに未登録です）' using errcode='22023';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.trimming_normalize_supplier_v1117(p_supplier text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select lower(regexp_replace(translate(coalesce(p_supplier,''),'（）()［］[]【】',''), '[[:space:]　・･ー_-]+', '', 'g'))
$function$
;
CREATE OR REPLACE FUNCTION public.trimming_require_role(p_roles text[])
 RETURNS profiles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_role text;
  v_roles text[];
begin
  v_profile := public.seika_current_profile_v1145();
  v_role := lower(btrim(v_profile.role::text));

  select coalesce(array_agg(lower(btrim(x))), '{}'::text[])
  into v_roles
  from unnest(coalesce(p_roles, '{}'::text[])) x
  where nullif(btrim(x), '') is not null;

  if not (v_role = any(v_roles)) then
    raise exception 'この操作を実行する権限がありません'
      using errcode = '42501';
  end if;

  return v_profile;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.trimming_week_start(p_day date)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select date_trunc('week', p_day::timestamp)::date
$function$
;
CREATE OR REPLACE FUNCTION public.update_app_state_if_version_v187(p_id text, p_expected_version bigint, p_data jsonb, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_row public.app_state%rowtype;
  app_role text;
  allowed_keys text[];
  changed_key text;
  next_data jsonb;
  next_version bigint;
  operation_uuid uuid;
begin
  if p_operation_id is not null then
    begin
      operation_uuid := p_operation_id::uuid;
    exception when invalid_text_representation then
      operation_uuid := (substr(md5(p_operation_id),1,8)||'-'||substr(md5(p_operation_id),9,4)||'-'||substr(md5(p_operation_id),13,4)||'-'||substr(md5(p_operation_id),17,4)||'-'||substr(md5(p_operation_id),21,12))::uuid;
    end;
  end if;

  app_role := public.current_app_role();
  if app_role is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select * into current_row
  from public.app_state
  where id = p_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;

  if current_row.version is distinct from p_expected_version then
    return jsonb_build_object(
      'ok', false,
      'code', 'VERSION_CONFLICT',
      'version', current_row.version,
      'updated_at', current_row.updated_at
    );
  end if;

  if p_operation_id is not null and current_row.last_operation_id = operation_uuid then
    return jsonb_build_object('ok', true, 'duplicate', true, 'version', current_row.version);
  end if;

  allowed_keys := case app_role
    when 'admin' then array[
      'settings','records','movements','notifications','items','purchaseMemos','purchaseMemoMeta','pins',
      'buyerAssignments','monthlyArchives','optimalStockChangeLogs','historyCleanups','duplicateDeleteLogs',
      'specialItems','specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems',
      'qrManagedPresetVersion','purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts'
    ]::text[]
    when 'worker' then array[
      'records','movements','notifications','items','purchaseMemos','purchaseMemoMeta','specialItems',
      'specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems','qrManagedPresetVersion',
      'purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts'
    ]::text[]
    when 'buyer' then array['settings','purchaseMemos','purchaseMemoMeta','operationLogs']::text[]
    when 'sales' then array['wasteRecords','operationLogs']::text[]
    when 'clerk' then array['wasteRecords','operationLogs']::text[]
    else array[]::text[]
  end;

  -- users / pins はクライアントから送信しないため、権限差分判定より先にサーバー値を復元する。
  next_data := coalesce(p_data, '{}'::jsonb);
  next_data := jsonb_set(next_data, '{users}', coalesce(current_row.data->'users', '[]'::jsonb), true);
  next_data := jsonb_set(next_data, '{pins}', coalesce(current_row.data->'pins', '{}'::jsonb), true);

  select k into changed_key
  from (
    select key as k from jsonb_object_keys(coalesce(current_row.data, '{}'::jsonb)) key
    union
    select key as k from jsonb_object_keys(next_data) key
  ) keys
  where not (k = any(allowed_keys))
    and current_row.data->k is distinct from next_data->k
  limit 1;

  if changed_key is not null then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN_FIELD', 'field', changed_key);
  end if;

  next_version := current_row.version + 1;

  update public.app_state
  set data = next_data,
      version = next_version,
      updated_at = now(),
      last_operation_id = operation_uuid,
      last_device_meta = coalesce(p_device_meta, '{}'::jsonb),
      last_operation_meta = coalesce(p_operation_meta, '{}'::jsonb)
  where id = p_id;

  return jsonb_build_object('ok', true, 'version', next_version, 'updated_at', now());
end
$function$
;
CREATE OR REPLACE FUNCTION public.update_app_state_if_version(p_id text, p_expected_version bigint, p_data jsonb, p_operation_id uuid DEFAULT NULL::uuid, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.app_state%rowtype;
begin
  select * into v_row
  from public.app_state
  where id = p_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', 'app_state が見つかりません');
  end if;

  if coalesce(v_row.version, 0) <> coalesce(p_expected_version, -1) then
    return jsonb_build_object(
      'ok', false,
      'conflict', true,
      'current_version', coalesce(v_row.version, 0),
      'updated_at', v_row.updated_at,
      'message', '他の端末で更新されています。再読み込みしてから操作してください。'
    );
  end if;

  update public.app_state
  set data = p_data,
      version = coalesce(v_row.version, 0) + 1,
      updated_at = now(),
      last_operation_id = p_operation_id,
      last_device_meta = coalesce(p_device_meta, '{}'::jsonb),
      last_operation_meta = coalesce(p_operation_meta, '{}'::jsonb)
  where id = p_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'version', v_row.version,
    'updated_at', v_row.updated_at
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.update_app_state_partial_v188(p_id text, p_expected_version bigint, p_changes jsonb, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_allowed text[];
  v_key text;
  v_ignored text[] := array[]::text[];
  v_applied integer := 0;
  v_next jsonb;
  v_next_version bigint;
  v_operation_uuid uuid;
begin
  v_operation_uuid := case when nullif(trim(coalesce(p_operation_id,'')),'') is null then null else public.seika_uuid_v188(p_operation_id) end;
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_id <> 'ishioka_inventory_production_v2' then raise exception '保存先が正しくありません' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_changes,'{}'::jsonb)) <> 'object' then raise exception '保存データが正しくありません' using errcode='22023'; end if;

  v_allowed := case v_profile.role
    when 'admin' then array['settings','records','movements','notifications','items','purchaseMemos','purchaseMemoMeta','buyerAssignments','monthlyArchives','optimalStockChangeLogs','historyCleanups','duplicateDeleteLogs','specialItems','specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems','qrManagedPresetVersion','purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts']::text[]
    when 'worker' then array['records','movements','notifications','items','purchaseMemos','purchaseMemoMeta','specialItems','specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems','qrManagedPresetVersion','purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts']::text[]
    when 'buyer' then array['settings','purchaseMemos','purchaseMemoMeta','operationLogs']::text[]
    when 'sales' then array['operationLogs']::text[]
    else array[]::text[]
  end;
  if coalesce(array_length(v_allowed,1),0)=0 then raise exception 'この権限では保存できません' using errcode='42501'; end if;
  for v_key in select jsonb_object_keys(p_changes) loop
    if not (v_key=any(v_allowed)) then
      v_ignored := array_append(v_ignored,v_key);
    end if;
  end loop;

  select * into v_state from public.app_state where id=p_id for update;
  if not found then return jsonb_build_object('ok',false,'message','保存先が見つかりません'); end if;
  if v_state.version is distinct from p_expected_version then
    return jsonb_build_object('ok',false,'conflict',true,'message','他端末の更新があります','version',v_state.version);
  end if;
  if v_operation_uuid is not null and v_state.last_operation_id=v_operation_uuid then
    return jsonb_build_object('ok',true,'duplicate',true,'version',v_state.version);
  end if;

  v_next:=coalesce(v_state.data,'{}'::jsonb);
  for v_key in select jsonb_object_keys(p_changes) loop
    if v_key=any(v_allowed) then
      v_next:=jsonb_set(v_next,array[v_key],p_changes->v_key,true);
      v_applied:=v_applied+1;
    end if;
  end loop;
  if v_applied=0 then
    return jsonb_build_object('ok',true,'noop',true,'version',v_state.version,'ignored_fields',to_jsonb(v_ignored));
  end if;
  v_next_version:=v_state.version+1;
  update public.app_state set data=v_next,version=v_next_version,updated_at=now(),last_operation_id=v_operation_uuid,last_device_meta=coalesce(p_device_meta,'{}'::jsonb),last_operation_meta=coalesce(p_operation_meta,'{}'::jsonb) where id=p_id;
  return jsonb_build_object('ok',true,'version',v_next_version,'updated_at',now(),'applied_count',v_applied,'ignored_fields',to_jsonb(v_ignored));
end
$function$
;
CREATE OR REPLACE FUNCTION public.update_purchase_price_v1127(p_original_week_start date, p_original_item_name text, p_original_origin text, p_original_supplier text, p_week_start date, p_item_name text, p_origin text, p_supplier text, p_price_yen_per_kg numeric, p_price_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles;
  v_original public.purchase_prices%rowtype;
  v_row public.purchase_prices%rowtype;
  v_old_week date;
  v_week date;
  v_item text;
  v_origin text;
  v_supplier text;
  v_type text;
  v_conflict public.purchase_prices%rowtype;
begin
  v_profile:=public.trimming_require_role(array['admin','worker','buyer','clerk']);
  if p_original_week_start is null or btrim(coalesce(p_original_item_name,''))='' then
    raise exception '編集元の週と品目は必須です' using errcode='22023';
  end if;
  if p_week_start is null or btrim(coalesce(p_item_name,''))='' or p_price_yen_per_kg is null or p_price_yen_per_kg<0 then
    raise exception '対象週、品目、0以上の税抜kg単価は必須です' using errcode='22023';
  end if;
  v_old_week:=public.trimming_week_start(p_original_week_start);
  select * into v_original from public.purchase_prices pp
  where pp.week_start=v_old_week and pp.item_name=btrim(p_original_item_name)
    and pp.origin=btrim(coalesce(p_original_origin,'')) and pp.supplier=btrim(coalesce(p_original_supplier,''))
  for update;
  if not found then return jsonb_build_object('ok',false,'not_found',true,'message','編集元の価格が見つかりません。再読み込みして確認してください。'); end if;

  v_type:=case when p_price_type='market' then 'market' else 'contract' end;
  v_week:=public.trimming_week_start(p_week_start);
  v_item:=btrim(p_item_name);
  v_origin:=case when v_type='market' then '' else btrim(coalesce(p_origin,'')) end;
  v_supplier:=case when v_type='market' then '市場' else btrim(coalesce(p_supplier,'')) end;
  if v_type='contract' and v_origin='' then raise exception '契約価格は産地が必須です' using errcode='22023'; end if;
  if v_type='contract' and v_supplier='' then raise exception '契約価格は仕入先が必須です' using errcode='22023'; end if;
  if v_type='contract' and public.trimming_normalize_supplier_v1117(v_supplier)='市場' then
    raise exception '仕入先「市場」は市場価格として登録してください' using errcode='22023';
  end if;

  if (v_original.week_start,v_original.item_name,v_original.origin,v_original.supplier)
       is distinct from (v_week,v_item,v_origin,v_supplier) then
    select * into v_conflict from public.purchase_prices pp
    where pp.week_start=v_week and pp.item_name=v_item and pp.origin=v_origin and pp.supplier=v_supplier
    for update;
    if found then
      return jsonb_build_object('ok',false,'conflict',true,'message','同じ週・品目・産地・仕入先の価格が既にあります。どちらも変更していません。');
    end if;
  end if;

  update public.purchase_prices set week_start=v_week,item_name=v_item,origin=v_origin,supplier=v_supplier,
    price_yen_per_kg=round(p_price_yen_per_kg,2),tax_type='税抜',price_type=v_type,updated_at=now(),updated_by=v_profile.id
  where id=v_original.id returning * into v_row;
  return jsonb_build_object('ok',true,'purchase_price',to_jsonb(v_row));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.update_trimming_job_work_date_v1197(p_job_id uuid, p_work_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job public.trimming_jobs%rowtype;
begin
  if p_work_date is null then
    return jsonb_build_object('ok', false, 'message', '作業日を指定してください');
  end if;

  update public.trimming_jobs
     set work_date = p_work_date,
         updated_at = pg_catalog.now()
   where id = p_job_id
  returning * into v_job;

  if not found then
    return jsonb_build_object('ok', false, 'message', '対象の日報が見つかりません');
  end if;

  perform public.recalc_trimming_job_price_v1195(p_job_id);

  select * into v_job from public.trimming_jobs where id = p_job_id;
  return jsonb_build_object('ok', true, 'job', pg_catalog.to_jsonb(v_job));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.upsert_item_aging_policy_v1136(p_id uuid DEFAULT NULL::uuid, p_item_id text DEFAULT NULL::text, p_item_name text DEFAULT NULL::text, p_fifo_enabled boolean DEFAULT true, p_attention_days integer DEFAULT 14, p_warning_days integer DEFAULT 30, p_critical_days integer DEFAULT 60, p_quality_review_requires_confirmation boolean DEFAULT true, p_active boolean DEFAULT true, p_effective_from date DEFAULT CURRENT_DATE, p_effective_to date DEFAULT NULL::date, p_change_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.profiles%rowtype;b jsonb;r public.seika_item_aging_policies_v1136%rowtype; iid text:=nullif(btrim(coalesce(p_item_id,'')), ''); inm text:=nullif(btrim(coalesce(p_item_name,'')), '');begin
 v:=public.trimming_require_role(array['admin']); if iid is null and inm is null then raise exception '品目IDまたは品目名が必要です';end if;
 if p_attention_days<0 or p_warning_days<p_attention_days or p_critical_days<p_warning_days or(p_effective_to is not null and p_effective_to<p_effective_from) then raise exception '滞留基準または期間が不正です';end if;
 if char_length(btrim(coalesce(p_change_reason,''))) not between 1 and 500 then raise exception '変更理由は1〜500文字で入力してください';end if;
 if p_id is null then insert into public.seika_item_aging_policies_v1136(item_id,item_name,fifo_enabled,attention_days,warning_days,critical_days,quality_review_requires_confirmation,active,effective_from,effective_to,created_by,updated_by,change_reason) values(iid,inm,coalesce(p_fifo_enabled,true),p_attention_days,p_warning_days,p_critical_days,coalesce(p_quality_review_requires_confirmation,true),coalesce(p_active,true),coalesce(p_effective_from,current_date),p_effective_to,v.id,v.id,btrim(p_change_reason)) returning * into r;
 else select to_jsonb(x) into b from public.seika_item_aging_policies_v1136 x where id=p_id for update; if not found then raise exception '対象ポリシーがありません';end if; update public.seika_item_aging_policies_v1136 set item_id=iid,item_name=inm,fifo_enabled=coalesce(p_fifo_enabled,true),attention_days=p_attention_days,warning_days=p_warning_days,critical_days=p_critical_days,quality_review_requires_confirmation=coalesce(p_quality_review_requires_confirmation,true),active=coalesce(p_active,true),effective_from=coalesce(p_effective_from,current_date),effective_to=p_effective_to,updated_at=now(),updated_by=v.id,change_reason=btrim(p_change_reason) where id=p_id returning * into r; end if;
 insert into public.seika_policy_audit_v1136(audited_by,audit_kind,subject_key,action,before_state,after_state,reason) values(v.id,'aging_policy',r.id::text,case when p_id is null then 'create' when not r.active then 'deactivate' else 'update'end,coalesce(b,'{}'),to_jsonb(r),btrim(p_change_reason)); return jsonb_build_object('ok',true,'policy',to_jsonb(r));end $function$
;
CREATE OR REPLACE FUNCTION public.upsert_my_push_subscription_v1144(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text DEFAULT NULL::text, p_device_label text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles;
declare v_endpoint text := btrim(coalesce(p_endpoint, ''));
declare v_p256dh text := btrim(coalesce(p_p256dh, ''));
declare v_auth text := btrim(coalesce(p_auth, ''));
declare v_id uuid;
begin
  v_profile := public.seika_quality_push_my_profile_v1144();
  if length(v_endpoint) < 12 or length(v_endpoint) > 8192 or v_endpoint !~ '^https://' then
    raise exception '通知先endpointが不正です';
  end if;
  if length(v_p256dh) < 16 or length(v_p256dh) > 1024 or length(v_auth) < 8 or length(v_auth) > 512 then
    raise exception '通知購読鍵が不正です';
  end if;
  -- 別の仕入担当者に既に紐付くendpointを奪えないようにする。
  if exists (select 1 from public.web_push_subscriptions_v1144 s where s.endpoint = v_endpoint and s.profile_id <> v_profile.id) then
    raise exception 'この端末の通知登録を更新できません';
  end if;
  insert into public.web_push_subscriptions_v1144(
    profile_id, endpoint, p256dh, auth_key, user_agent, device_label, active,
    failure_count, last_failure_at, updated_at
  ) values (
    v_profile.id, v_endpoint, v_p256dh, v_auth,
    nullif(left(coalesce(p_user_agent, ''), 1000), ''),
    nullif(left(coalesce(p_device_label, ''), 200), ''), true, 0, null, now()
  ) on conflict (endpoint) do update set
    profile_id = excluded.profile_id,
    p256dh = excluded.p256dh,
    auth_key = excluded.auth_key,
    user_agent = excluded.user_agent,
    device_label = excluded.device_label,
    active = true,
    failure_count = 0,
    last_failure_at = null,
    updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'subscription_id', v_id);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.upsert_purchase_price_v1117(p_week_start date, p_item_name text, p_origin text, p_supplier text, p_price_yen_per_kg numeric, p_price_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles; v_week date; v_row public.purchase_prices; v_type text; v_supplier text; v_origin text;
begin
  v_profile:=public.trimming_require_role(array['admin','worker','buyer','clerk']);
  v_type:=case when p_price_type='market' then 'market' else 'contract' end;
  v_supplier:=case when v_type='market' then '市場' else btrim(coalesce(p_supplier,'')) end;
  v_origin:=case when v_type='market' then '' else btrim(coalesce(p_origin,'')) end;
  if p_week_start is null or btrim(coalesce(p_item_name,''))='' or p_price_yen_per_kg is null or p_price_yen_per_kg<0 then
    raise exception '適用日、品目、0以上の税抜kg単価は必須です' using errcode='22023';
  end if;
  if v_type='contract' and v_origin='' then raise exception '契約価格は産地が必須です' using errcode='22023'; end if;
  if v_type='contract' and v_supplier='' then raise exception '契約価格は仕入先が必須です' using errcode='22023'; end if;
  if v_type='contract' and public.trimming_normalize_supplier_v1117(v_supplier)='市場' then
    raise exception '仕入先「市場」は市場価格として登録してください' using errcode='22023';
  end if;
  v_week:=public.trimming_week_start(p_week_start);
  insert into public.purchase_prices(week_start,item_name,origin,supplier,price_yen_per_kg,tax_type,price_type,created_by,updated_by)
  values(v_week,btrim(p_item_name),v_origin,v_supplier,round(p_price_yen_per_kg,2),'税抜',v_type,v_profile.id,v_profile.id)
  on conflict(week_start,item_name,origin,supplier) do update set price_yen_per_kg=excluded.price_yen_per_kg,tax_type='税抜',price_type=excluded.price_type,updated_at=now(),updated_by=v_profile.id
  returning * into v_row;
  return jsonb_build_object('ok',true,'purchase_price',to_jsonb(v_row));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.upsert_purchase_price(p_week_start date, p_item_name text, p_origin text, p_supplier text, p_price_yen_per_kg numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles; v_week date; v_row public.purchase_prices;
begin
  v_profile := public.trimming_require_role(array['admin','worker','buyer','clerk']);
  if p_week_start is null or btrim(coalesce(p_item_name,''))='' or p_price_yen_per_kg is null or p_price_yen_per_kg < 0 then
    raise exception '週、品目、0以上の税抜kg単価は必須です' using errcode='22023';
  end if;
  v_week := public.trimming_week_start(p_week_start);
  insert into public.purchase_prices(week_start,item_name,origin,supplier,price_yen_per_kg,tax_type,created_by,updated_by)
  values(v_week,btrim(p_item_name),btrim(coalesce(p_origin,'')),btrim(coalesce(p_supplier,'')),round(p_price_yen_per_kg,2),'税抜',v_profile.id,v_profile.id)
  on conflict (week_start,item_name,origin,supplier) do update set price_yen_per_kg=excluded.price_yen_per_kg, tax_type='税抜', updated_at=now(), updated_by=v_profile.id
  returning * into v_row;
  return jsonb_build_object('ok',true,'purchase_price',to_jsonb(v_row));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v119_confirm_inventory_count_document(p_id text, p_expected_version bigint, p_session_id text, p_document_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new_session jsonb;v_data jsonb;v_version bigint;v_path text:=left(btrim(coalesce(p_document_path,'')),500);
begin
  if p_id is null or p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です' using errcode='22023'; end if;
  select * into v_profile from public.seika_inventory_count_profile_v1119();if not found or v_profile.role<>'admin' then raise exception '文書管理の保存確認は管理者のみです' using errcode='42501';end if;
  if v_path='' then raise exception '文書管理の保存先が必要です' using errcode='22023';end if;
  v_state:=public.seika_inventory_count_lock_v1119(p_id,p_expected_version);if v_state is null then return jsonb_build_object('ok',false,'conflict',true,'message','他端末で更新されています。最新データを読み込んでください');end if;
  v_session:=public.seika_inventory_count_session_v1119(v_state.data,p_session_id);if v_session->>'isTest'='true' then raise exception 'テスト棚卸しは文書管理の正式保存対象ではありません' using errcode='22023';end if;if v_session->>'status'<>'confirmed' or v_session->>'priceStatus'<>'priced' or coalesce(v_session->>'excelExportedAt','')='' then raise exception '単価入力済みでExcel出力記録がある棚卸しだけ保存確認できます' using errcode='22023';end if;
  v_new_session:=v_session||jsonb_build_object('documentSavedAt',now(),'documentSavedBy',coalesce(v_profile.display_name,''),'documentSavedById',v_profile.id,'documentSavedPath',v_path,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::integer,0)+1);
  v_data:=public.seika_inventory_count_replace_session_v1119(v_state.data,p_session_id,v_new_session);update public.app_state set data=v_data,version=version+1,updated_at=now() where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'session_id',p_session_id);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v119_mark_inventory_count_excel_export(p_id text, p_expected_version bigint, p_session_id text, p_file_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new_session jsonb;v_data jsonb;v_version bigint;v_file text:=left(btrim(coalesce(p_file_name,'')),240);
begin
  if p_id is null or p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です' using errcode='22023'; end if;
  select * into v_profile from public.seika_inventory_count_profile_v1119();if not found or v_profile.role not in ('admin','sales','clerk') then raise exception '棚卸しExcelを出力できるのは管理者・営業・事務です' using errcode='42501'; end if;
  if v_file='' then raise exception 'Excelファイル名が必要です' using errcode='22023'; end if;
  v_state:=public.seika_inventory_count_lock_v1119(p_id,p_expected_version);if v_state is null then return jsonb_build_object('ok',false,'conflict',true,'message','他端末で更新されています。最新データを読み込んでください');end if;
  v_session:=public.seika_inventory_count_session_v1119(v_state.data,p_session_id);if not ((v_session->>'status'='confirmed' and coalesce(v_session->>'isTest','false')<>'true') or (v_session->>'status'='test_confirmed' and v_session->>'isTest'='true' and v_session->>'mode'='test')) or v_session->>'priceStatus'<>'priced' then raise exception '単価入力済みの確定棚卸しだけExcel出力を記録できます' using errcode='22023';end if;if v_session->>'isTest'='true' and position('TEST' in upper(v_file))=0 then raise exception 'テスト棚卸しのExcelファイル名にはTESTを含めてください' using errcode='22023';end if;
  v_new_session:=v_session||jsonb_build_object('excelExportedAt',now(),'excelExportedBy',coalesce(v_profile.display_name,''),'excelExportedById',v_profile.id,'excelFileName',v_file,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::integer,0)+1);
  v_data:=public.seika_inventory_count_replace_session_v1119(v_state.data,p_session_id,v_new_session);update public.app_state set data=v_data,version=version+1,updated_at=now() where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'session_id',p_session_id);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v119_purge_inventory_count_details(p_id text, p_expected_version bigint, p_session_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new_session jsonb;v_data jsonb;v_version bigint;v_confirmed timestamptz;v_line_count integer;v_qr_line_count integer;v_logs jsonb;v_audit jsonb;
begin
  if p_id is null or p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です' using errcode='22023'; end if;
  select * into v_profile from public.seika_inventory_count_profile_v1119();if not found or v_profile.role<>'admin' then raise exception '棚卸し明細を削除できるのは管理者のみです' using errcode='42501';end if;
  v_state:=public.seika_inventory_count_lock_v1119(p_id,p_expected_version);if v_state is null then return jsonb_build_object('ok',false,'conflict',true,'message','他端末で更新されています。最新データを読み込んでください');end if;
  v_session:=public.seika_inventory_count_session_v1119(v_state.data,p_session_id);if v_session->>'isTest'='true' then raise exception 'テスト棚卸しは3か月明細削除の対象外です' using errcode='22023';end if;v_confirmed:=nullif(v_session->>'confirmedAt','')::timestamptz;
  if v_session->>'status'<>'confirmed' or coalesce(v_session->>'reversedAt','')<>'' or coalesce(v_session->>'priceStatus','')<>'priced' or coalesce(v_session->>'excelExportedAt','')='' or coalesce(v_session->>'documentSavedAt','')='' then raise exception '確定・単価入力・Excel出力・文書管理保存確認が完了した棚卸しだけ削除できます' using errcode='22023';end if;
  if v_confirmed is null or now()<v_confirmed+interval '3 months' then raise exception '確定から3か月経過後に削除できます' using errcode='22023';end if;
  if coalesce(v_session->>'detailsDeletedAt','')<>'' then return jsonb_build_object('ok',true,'already_deleted',true,'version',v_state.version,'session_id',p_session_id);end if;
  v_line_count:=jsonb_array_length(coalesce(v_session->'lines','[]'::jsonb));v_qr_line_count:=jsonb_array_length(coalesce(v_session->'qrLines','[]'::jsonb));
  v_new_session:=v_session||jsonb_build_object('lines','[]'::jsonb,'qrLines','[]'::jsonb,'detailsDeletedAt',now(),'detailsDeletedBy',coalesce(v_profile.display_name,''),'detailsDeletedById',v_profile.id,'deletedNormalLineCount',v_line_count,'deletedQrLineCount',v_qr_line_count,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::integer,0)+1);
  v_audit:=jsonb_build_object('id',extensions.gen_random_uuid()::text,'type','棚卸し','action','明細削除','sessionId',p_session_id,'user',coalesce(v_profile.display_name,''),'userId',v_profile.id,'role',v_profile.role,'detail',format('通常 %s件 / QR %s件を3か月保持後に削除',v_line_count,v_qr_line_count),'createdAt',now());
  v_logs:=case when jsonb_typeof(v_state.data->'operationLogs')='array' then v_state.data->'operationLogs' else '[]'::jsonb end||jsonb_build_array(v_audit);
  select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into v_logs from jsonb_array_elements(v_logs) with ordinality x(value,ord) where ord>greatest(jsonb_array_length(v_logs)-500,0);
  v_data:=jsonb_set(public.seika_inventory_count_replace_session_v1119(v_state.data,p_session_id,v_new_session),'{operationLogs}',v_logs,true);
  update public.app_state set data=v_data,version=version+1,updated_at=now() where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'session_id',p_session_id,'deleted_normal_line_count',v_line_count,'deleted_qr_line_count',v_qr_line_count);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v119_save_inventory_count_prices(p_id text, p_expected_version bigint, p_session_id text, p_prices jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_line jsonb;v_input jsonb;v_id text;v_price numeric;v_actual numeric;v_kg numeric;v_amount numeric;v_normal jsonb:='[]'::jsonb;v_qr jsonb:='[]'::jsonb;v_new jsonb;v_data jsonb;v_version bigint;v_count integer:=0;v_total numeric:=0;
begin
 if p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','sales','clerk') then raise exception '単価を保存できるのは管理者・営業・事務です' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found or v_state.version<>p_expected_version then return jsonb_build_object('ok',false,'conflict',true,'message','他端末で更新されています');end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id;v_session:=public.seika_inventory_count_normalize_session_v123(v_session);if v_session->>'status' not in ('confirmed','test_confirmed') then raise exception '確定済みの棚卸しだけ単価を保存できます';end if;
 for v_line in select value from jsonb_array_elements(coalesce(v_session->'lines','[]'::jsonb)) loop v_id:=v_line->>'lineId';select value into v_input from jsonb_array_elements(p_prices) where value->>'lineId'=v_id and coalesce(value->>'qrKey','')='';if v_input is null then raise exception '通常在庫の単価行が不足しています';end if;v_actual:=public.seika_inventory_count_decimal_optional_v123(v_line->>'actualQty','実数');if v_actual=0 then v_price:=0;v_kg:=0;v_amount:=0;else v_price:=public.seika_inventory_count_decimal_optional_v123(v_input->>'unitPriceYenPerKg','単価');if v_price is null or v_price<0 then raise exception '%：単価は0以上で入力してください',v_line->>'itemName';end if;v_kg:=public.seika_inventory_count_line_kg_v1119(v_line,false);if v_kg is null or v_kg<=0 then raise exception '%：実数はありますがkg換算できません。1単位あたりkgを確認してください',v_line->>'itemName';end if;v_amount:=round(v_kg*v_price,0);end if;v_normal:=v_normal||jsonb_build_array(v_line||jsonb_build_object('unitPriceYenPerKg',v_price,'countedKg',v_kg,'amountYen',v_amount));v_count:=v_count+1;v_total:=v_total+v_amount;end loop;
 for v_line in select value from jsonb_array_elements(coalesce(v_session->'qrLines','[]'::jsonb)) loop v_id:=coalesce(v_line->>'qrKey',v_line->>'qr_key');select value into v_input from jsonb_array_elements(p_prices) where value->>'qrKey'=v_id and coalesce(value->>'lineId','')='';if v_input is null then raise exception 'QR在庫の単価行が不足しています';end if;v_actual:=public.seika_inventory_count_decimal_optional_v123(v_line->>'actualQty','実数');if v_actual=0 then v_price:=0;v_kg:=0;v_amount:=0;else v_price:=public.seika_inventory_count_decimal_optional_v123(v_input->>'unitPriceYenPerKg','単価');if v_price is null or v_price<0 then raise exception '%：単価は0以上で入力してください',v_line->>'itemName';end if;v_kg:=public.seika_inventory_count_line_kg_v1119(v_line,true);if v_kg is null or v_kg<=0 then raise exception '%：実数はありますがkg換算できません。QR内容量または重量を確認してください',v_line->>'itemName';end if;v_amount:=round(v_kg*v_price,0);end if;v_qr:=v_qr||jsonb_build_array(v_line||jsonb_build_object('unitPriceYenPerKg',v_price,'countedKg',v_kg,'amountYen',v_amount));v_count:=v_count+1;v_total:=v_total+v_amount;end loop;
 v_new:=v_session||jsonb_build_object('lines',v_normal,'qrLines',v_qr,'priceStatus','priced','pricedAt',now(),'pricedBy',coalesce(v_profile.display_name,''),'pricedById',v_profile.id,'priceTotalYen',v_total,'priceLineCount',v_count,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1);v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);update public.app_state set data=v_data,version=version+1,updated_at=now() where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'line_count',v_count,'total_amount_yen',v_total);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v120_confirm_inventory_count_test(p_id text, p_expected_version bigint, p_session_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_data jsonb;v_version bigint;
begin
 if p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role<>'admin' then raise exception 'テスト棚卸しを確定できるのは管理者のみです' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found or v_state.version<>p_expected_version then return jsonb_build_object('ok',false,'conflict',true,'message','他端末で更新されています');end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id;v_session:=public.seika_inventory_count_normalize_session_v123(v_session);if coalesce(v_session->>'isTest','false')<>'true' or v_session->>'normalStatus'<>'submitted' or v_session->>'qrCountStatus'<>'submitted' then raise exception '通常・QRの両工程が入力完了したテスト棚卸しだけ確定できます';end if;v_new:=v_session||jsonb_build_object('normalStatus','confirmed','qrCountStatus','confirmed','status','test_confirmed','priceStatus','waiting_price','confirmedAt',now(),'confirmedBy',coalesce(v_profile.display_name,''),'confirmedById',v_profile.id,'inventoryApplied',false,'qrApplied',false,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1);v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);update public.app_state set data=v_data,version=version+1,updated_at=now() where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'session_id',p_session_id,'inventory_applied',false,'qr_applied',false);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v120_delete_unconfirmed_inventory_count(p_id text, p_expected_version bigint, p_session_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_data jsonb;v_sessions jsonb;v_logs jsonb;v_audit jsonb;v_version bigint;v_reason text:=btrim(coalesce(p_reason,''));v_match_count integer;v_lines integer;v_qr integer;
begin
  if p_id is null or p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です' using errcode='22023';end if;
  select * into v_profile from public.seika_inventory_count_profile_v1119();if not found or v_profile.role<>'admin' then raise exception '確定前棚卸しを削除できるのは管理者のみです' using errcode='42501';end if;
  if char_length(v_reason)<2 or char_length(v_reason)>500 then raise exception '削除理由を2〜500文字で入力してください' using errcode='22023';end if;
  v_state:=public.seika_inventory_count_lock_v1119(p_id,p_expected_version);if v_state is null then return jsonb_build_object('ok',false,'conflict',true,'message','他端末で更新されています。最新データを読み込んでください');end if;
  select count(*) into v_match_count from jsonb_array_elements(v_state.data->'inventoryCounts'->'sessions') x where x.value->>'id'=p_session_id;
  if v_match_count<>1 then raise exception '対象棚卸しが見つからないか、IDが重複しています' using errcode='22023';end if;
  v_session:=public.seika_inventory_count_session_v1119(v_state.data,p_session_id);
  if v_session->>'status' not in ('counting','submitted','test_counting','test_submitted','cancelled') then raise exception '在庫反映前の入力中・確認待ち・破棄済み棚卸しだけ削除できます' using errcode='22023';end if;
  v_lines:=jsonb_array_length(coalesce(v_session->'lines','[]'::jsonb));v_qr:=jsonb_array_length(coalesce(v_session->'qrLines','[]'::jsonb));
  select coalesce(jsonb_agg(value order by ord) filter(where value->>'id'<>p_session_id),'[]'::jsonb) into v_sessions from jsonb_array_elements(v_state.data->'inventoryCounts'->'sessions') with ordinality x(value,ord);
  v_audit:=jsonb_build_object('id',extensions.gen_random_uuid()::text,'type','棚卸し','action','確定前セッション削除','sessionId',p_session_id,'room',v_session->>'room','user',coalesce(v_profile.display_name,''),'userId',v_profile.id,'role',v_profile.role,'reason',v_reason,'detail',format('%s / %s / 通常 %s件 / QR %s件',coalesce(v_session->>'countNo',''),coalesce(v_session->>'status',''),v_lines,v_qr),'before',jsonb_build_object('countNo',v_session->>'countNo','status',v_session->>'status','room',v_session->>'room','revision',v_session->>'revision','normalLineCount',v_lines,'qrLineCount',v_qr,'startedAt',v_session->>'startedAt','submittedAt',v_session->>'submittedAt','isTest',coalesce(v_session->'isTest','false'::jsonb)),'createdAt',now());
  v_logs:=(case when jsonb_typeof(v_state.data->'operationLogs')='array' then v_state.data->'operationLogs' else '[]'::jsonb end)||jsonb_build_array(v_audit);
  select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into v_logs from jsonb_array_elements(v_logs) with ordinality x(value,ord) where ord>greatest(jsonb_array_length(v_logs)-500,0);
  v_data:=jsonb_set(jsonb_set(v_state.data,'{inventoryCounts,sessions}',v_sessions,true),'{operationLogs}',v_logs,true);
  update public.app_state set data=v_data,version=version+1,updated_at=now() where id=v_state.id returning version into v_version;
  return jsonb_build_object('ok',true,'version',v_version,'session_id',p_session_id,'deleted_normal_line_count',v_lines,'deleted_qr_line_count',v_qr);
end;$function$
;
CREATE OR REPLACE FUNCTION public.v123_create_inventory_count_session(p_id text, p_session jsonb, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_data jsonb;v_version bigint;v_now timestamptz:=now();
begin
 if p_id<>'ishioka_inventory_production_v2' or jsonb_typeof(p_session)<>'object' or nullif(btrim(p_session->>'id'),'') is null or nullif(btrim(p_operation_id),'') is null then raise exception '棚卸し開始データが不正です' using errcode='22023';end if;
 select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','worker') then raise exception '棚卸し開始は管理者・青果社員のみです' using errcode='42501';end if;
 select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002';end if;
 if exists(select 1 from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session->>'id') then return jsonb_build_object('ok',true,'idempotent',true,'version',v_state.version);end if;
 if exists(select 1 from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'room'=p_session->>'room' and coalesce(value->>'status','') in ('counting','submitted','test_counting','test_submitted')) then raise exception 'この冷蔵庫には進行中の棚卸しがあります' using errcode='23505';end if;
 v_session:=public.seika_inventory_count_normalize_session_v123(p_session||jsonb_build_object('startedAt',coalesce(p_session->>'startedAt',v_now::text),'startedBy',coalesce(v_profile.display_name,''),'startedById',v_profile.id,'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'revision',1,'v123OperationIds',jsonb_build_array(jsonb_build_object('id',p_operation_id,'action','create','at',v_now))));
 v_data:=jsonb_set(v_state.data,'{inventoryCounts,sessions}',coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)||jsonb_build_array(v_session),true);
 update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;
 return jsonb_build_object('ok',true,'version',v_version,'session_id',v_session->>'id','normalRevision',(v_session->>'normalRevision')::bigint,'qrRevision',(v_session->>'qrRevision')::bigint);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v123_return_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_revision bigint;v_data jsonb;v_version bigint;v_now timestamptz:=now();
begin
 if p_id<>'ishioka_inventory_production_v2' or p_section not in ('normal','qr') then raise exception '引数が不正です' using errcode='22023';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role<>'admin' then raise exception '差戻しできるのは管理者のみです' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002';end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id;v_session:=public.seika_inventory_count_normalize_session_v123(v_session);v_revision:=case when p_section='normal' then (v_session->>'normalRevision')::bigint else (v_session->>'qrRevision')::bigint end;if p_expected_section_revision<>v_revision then return jsonb_build_object('ok',false,'conflict',true,'message','別端末で更新されています');end if;if (case when p_section='normal' then v_session->>'normalStatus' else v_session->>'qrCountStatus' end)<>'submitted' then raise exception '提出済みの工程だけ差戻しできます' using errcode='22023';end if;v_new:=case when p_section='normal' then v_session||jsonb_build_object('normalStatus','incomplete','normalRevision',v_revision+1,'normalReturnedAt',v_now,'normalReturnedBy',coalesce(v_profile.display_name,''),'normalSubmittedAt',null,'normalSubmittedBy',null) else v_session||jsonb_build_object('qrCountStatus','incomplete','qrRevision',v_revision+1,'qrReturnedAt',v_now,'qrReturnedBy',coalesce(v_profile.display_name,''),'qrSubmittedAt',null,'qrSubmittedBy',null) end;v_new:=v_new||jsonb_build_object('status',public.seika_inventory_count_v123_status(v_new),'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1);v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'sectionRevision',v_revision+1,'status',v_new->>'status');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v123_save_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint, p_entries jsonb, p_action text, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_lines jsonb:='[]'::jsonb;v_source jsonb;v_entry jsonb;v_entry_count integer;v_source_count integer;v_id text;v_actual numeric;v_actual_weight numeric;v_kg numeric;v_pack numeric;v_cases numeric;v_remainder numeric;v_weight_entries jsonb;v_weight jsonb;v_sum numeric;v_active boolean;v_is_kg boolean;v_missing integer:=0;v_revision bigint;v_data jsonb;v_version bigint;v_logs jsonb;v_message text;v_existing_op jsonb;v_now timestamptz:=now();
begin
 if p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です' using errcode='22023';end if;
 if p_section not in ('normal','qr') or p_action not in ('draft','submit') then raise exception '保存工程または操作が不正です' using errcode='22023';end if;
 if p_session_id is null or btrim(p_session_id)='' or p_operation_id is null or char_length(p_operation_id)>200 then raise exception '棚卸しIDまたは操作IDが不正です' using errcode='22023';end if;
 if jsonb_typeof(p_entries)<>'array' then raise exception '入力データの形式が不正です' using errcode='22023';end if;
 select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','worker') then raise exception '棚卸しを保存できるのは管理者・青果社員です' using errcode='42501';end if;
 select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002';end if;
 select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id limit 1;if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002';end if;
 v_session:=public.seika_inventory_count_normalize_session_v123(v_session);
 -- Same operation retried after a lost response: return success without modifying inventory again.
 select value into v_existing_op from jsonb_array_elements(coalesce(v_session->'v123OperationIds','[]'::jsonb)) where value->>'id'=p_operation_id limit 1;
 if v_existing_op is not null then return jsonb_build_object('ok',true,'idempotent',true,'version',v_state.version,'sectionRevision',case when p_section='normal' then (v_session->>'normalRevision')::bigint else (v_session->>'qrRevision')::bigint end,'status',v_session->>'status','message','同じ保存操作はすでに反映済みです');end if;
 v_revision:=case when p_section='normal' then coalesce((v_session->>'normalRevision')::bigint,0) else coalesce((v_session->>'qrRevision')::bigint,0) end;
 if p_expected_section_revision is null or p_expected_section_revision<>v_revision then return jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'sectionRevision',v_revision,'message','この工程を別端末で更新しています。入力内容は端末に保持しています。最新データを確認してください');end if;
 if (p_section='normal' and coalesce(v_session->>'normalStatus','') in ('confirmed')) or (p_section='qr' and coalesce(v_session->>'qrCountStatus','') in ('confirmed')) then raise exception '確定済みの工程は変更できません' using errcode='22023';end if;
 select count(*) into v_source_count from jsonb_array_elements(case when p_section='normal' then coalesce(v_session->'lines','[]'::jsonb) else coalesce(v_session->'qrLines','[]'::jsonb) end);
 if jsonb_array_length(p_entries)<>v_source_count then raise exception '入力件数が棚卸し対象件数と一致しません。画面を再読込してください' using errcode='22023';end if;
 for v_source in select value from jsonb_array_elements(case when p_section='normal' then coalesce(v_session->'lines','[]'::jsonb) else coalesce(v_session->'qrLines','[]'::jsonb) end) loop
   v_id:=case when p_section='normal' then nullif(btrim(v_source->>'lineId'),'') else nullif(btrim(coalesce(v_source->>'qrKey',v_source->>'qr_key')),'') end;
   if v_id is null then raise exception '棚卸し明細IDが不正です' using errcode='22023';end if;
   select count(*) into v_entry_count from jsonb_array_elements(p_entries) where nullif(btrim(value->>'id'),'')=v_id;
   if v_entry_count<>1 then raise exception '入力明細が不足または重複しています' using errcode='22023';end if;
   select value into v_entry from jsonb_array_elements(p_entries) where nullif(btrim(value->>'id'),'')=v_id limit 1;
   v_is_kg:=p_section='normal' and (lower(coalesce(v_source->>'unit','kg'))='kg' or coalesce(v_source->>'type','')='normal');
   if v_is_kg then
     if jsonb_typeof(v_entry->'weightEntries')<>'array' or jsonb_array_length(v_entry->'weightEntries')>20 then raise exception '%：量目明細は1〜20行で入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
     v_sum:=0;v_active:=false;v_weight_entries:='[]'::jsonb;
     for v_weight in select value from jsonb_array_elements(v_entry->'weightEntries') loop
       v_pack:=public.seika_inventory_count_decimal_optional_v123(v_weight->>'packKg','量目kg');v_cases:=public.seika_inventory_count_decimal_optional_v123(v_weight->>'caseCount','ケース数');
       if v_pack is null and v_cases is null then v_weight_entries:=v_weight_entries||jsonb_build_array(jsonb_build_object('id',coalesce(nullif(btrim(v_weight->>'id'),''),extensions.gen_random_uuid()::text),'packKg','','caseCount',''));
       elsif v_pack is null or v_pack<=0 or v_cases is null or v_cases<0 then raise exception '%：量目kgは0より大きく、ケース数は0以上で入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';
       else v_sum:=v_sum+v_pack*v_cases;v_active:=true;v_weight_entries:=v_weight_entries||jsonb_build_array(jsonb_build_object('id',coalesce(nullif(btrim(v_weight->>'id'),''),extensions.gen_random_uuid()::text),'packKg',v_pack,'caseCount',v_cases));end if;
     end loop;
     v_remainder:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'remainderKg','端数kg');if v_remainder is not null and v_remainder<0 then raise exception '%：端数kgは0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if v_remainder is not null then v_sum:=v_sum+v_remainder;v_active:=true;end if;
     v_actual:=case when v_active then round(v_sum,3) else null end;
     if p_action='submit' and coalesce((v_entry->>'supplierRequired')::boolean,false) and btrim(coalesce(v_entry->>'supplier',''))='' then raise exception '%：仕入先を入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;v_source:=v_source||jsonb_build_object('weightEntries',v_weight_entries,'remainderKg',coalesce(v_remainder::text,''),'inputMode','weight_entries','actualQty',v_actual,'supplier',left(btrim(coalesce(v_entry->>'supplier','')),160),'supplierRequired',coalesce((v_entry->>'supplierRequired')::boolean,false),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000),'status',case when v_actual is null then 'unentered' else 'entered' end);
   else
     v_actual:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty','実数');if v_actual is not null and v_actual<0 then raise exception '%：実数は0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
     if p_section='normal' then v_kg:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'kgPerUnit','1単位あたりkg');if v_kg is not null and v_kg<=0 then raise exception '%：1単位あたりkgは0より大きい値です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if p_action='submit' and coalesce((v_entry->>'supplierRequired')::boolean,false) and btrim(coalesce(v_entry->>'supplier',''))='' then raise exception '%：仕入先を入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;v_source:=v_source||jsonb_build_object('actualQty',v_actual,'kgPerUnit',coalesce(v_kg::text,''),'supplier',left(btrim(coalesce(v_entry->>'supplier','')),160),'supplierRequired',coalesce((v_entry->>'supplierRequired')::boolean,false),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000),'status',case when v_actual is null then 'unentered' else 'entered' end);
     else v_actual_weight:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualWeightKg','棚卸し重量kg');if v_actual_weight is not null and v_actual_weight<0 then raise exception '%：棚卸し重量kgは0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if p_action='submit' and coalesce(v_source->>'unit','')='基' and v_actual is not null and (v_actual_weight is null) and (coalesce((v_source->>'snapshotTotalWeight')::numeric,0)<=0 or coalesce((v_source->>'snapshotInitialQty')::numeric,0)<=0) then raise exception '%：大型容器は棚卸し重量kgを入力してください',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;v_source:=v_source||jsonb_build_object('actualQty',v_actual,'actualWeightKg',v_actual_weight,'outQty',coalesce(public.seika_inventory_count_decimal_optional_v123(v_entry->>'outQty','簡単出庫'),0),'destination',left(btrim(coalesce(v_entry->>'destination','')),160),'shipTiming',left(btrim(coalesce(v_entry->>'shipTiming','')),80),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000),'status',case when v_actual is null then 'unentered' else 'entered' end);end if;
   end if;
   if (v_source->>'actualQty') is null or v_source->>'actualQty'='' then v_missing:=v_missing+1;end if;
   v_source:=v_source||jsonb_build_object('countedAt',case when (v_source->>'actualQty') is null then null else v_now end,'countedBy',case when (v_source->>'actualQty') is null then null else coalesce(v_profile.display_name,'') end,'countedById',case when (v_source->>'actualQty') is null then null else v_profile.id end);
   v_lines:=v_lines||jsonb_build_array(v_source);
 end loop;
 if p_action='submit' and v_missing>0 then raise exception '未入力が%件あります。未入力のまま保存する場合は下書き保存を選んでください',v_missing using errcode='22023';end if;
 v_new:=case when p_section='normal' then v_session||jsonb_build_object('lines',v_lines,'normalStatus',case when p_action='submit' then 'submitted' when v_missing>0 then 'incomplete' else 'counting' end,'normalRevision',v_revision+1,'normalSavedAt',v_now,'normalSavedBy',coalesce(v_profile.display_name,''),'normalSavedById',v_profile.id,'normalSubmittedAt',case when p_action='submit' then v_now else null end,'normalSubmittedBy',case when p_action='submit' then coalesce(v_profile.display_name,'') else null end,'normalSubmittedById',case when p_action='submit' then v_profile.id else null end) else v_session||jsonb_build_object('qrLines',v_lines,'qrCountStatus',case when p_action='submit' then 'submitted' when v_missing>0 then 'incomplete' else 'counting' end,'qrRevision',v_revision+1,'qrSavedAt',v_now,'qrSavedBy',coalesce(v_profile.display_name,''),'qrSavedById',v_profile.id,'qrSubmittedAt',case when p_action='submit' then v_now else null end,'qrSubmittedBy',case when p_action='submit' then coalesce(v_profile.display_name,'') else null end,'qrSubmittedById',case when p_action='submit' then v_profile.id else null end) end;
 v_new:=v_new||jsonb_build_object('status',public.seika_inventory_count_v123_status(v_new),'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1,'v123OperationIds',(coalesce(v_session->'v123OperationIds','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',p_operation_id,'section',p_section,'action',p_action,'at',v_now))));
 select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into v_logs from jsonb_array_elements(v_new->'v123OperationIds') with ordinality x(value,ord) where ord>greatest(jsonb_array_length(v_new->'v123OperationIds')-50,0);v_new:=jsonb_set(v_new,'{v123OperationIds}',v_logs,true);
 v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);
 v_data:=public.seika_inventory_count_v123_append_log(v_data,jsonb_build_object('id',extensions.gen_random_uuid()::text,'type','棚卸し','action',case when p_action='submit' then '工程入力完了' else '工程下書き保存' end,'section',p_section,'sessionId',p_session_id,'user',coalesce(v_profile.display_name,''),'userId',v_profile.id,'role',v_profile.role,'detail',format('%s / 未入力 %s件',case when p_section='normal' then '通常・その他在庫' else 'QR在庫' end,v_missing),'operationId',p_operation_id,'createdAt',v_now));
 update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;
 v_message:=case when p_action='submit' then '入力完了として提出しました' when v_missing>0 then '未入力を含む下書きを保存しました' else '下書きを保存しました' end;
 return jsonb_build_object('ok',true,'version',v_version,'sectionRevision',v_revision+1,'status',v_new->>'status','normalStatus',v_new->>'normalStatus','qrCountStatus',v_new->>'qrCountStatus','missing',v_missing,'message',v_message);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v124_confirm_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_data jsonb;v_lines jsonb;v_line jsonb;v_records jsonb;v_special jsonb;v_key text;v_status text;v_revision bigint;v_version bigint;v_now timestamptz:=now();
begin
 if p_id<>'ishioka_inventory_production_v2' or p_section not in ('normal','qr','kataoka') or nullif(btrim(p_operation_id),'') is null then raise exception '確定引数が不正です' using errcode='22023';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role<>'admin' then raise exception '確定できるのは管理者のみです' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません';end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id;v_session:=public.seika_inventory_count_normalize_session_v124(v_session);v_key:=case p_section when 'normal' then 'normalRevision' when 'qr' then 'qrRevision' else 'kataokaRevision' end;v_status:=case p_section when 'normal' then 'normalStatus' when 'qr' then 'qrCountStatus' else 'kataokaStatus' end;v_revision:=coalesce((v_session->>v_key)::bigint,0);if p_expected_section_revision<>v_revision then return jsonb_build_object('ok',false,'conflict',true,'message','別端末で更新されています');end if;if v_session->>v_status='confirmed' then return jsonb_build_object('ok',true,'idempotent',true,'version',v_state.version);end if;if v_session->>v_status<>'submitted' then raise exception '提出済み工程だけ確定できます' using errcode='22023';end if;
 v_records:=coalesce(v_state.data->'records','[]'::jsonb);v_special:=coalesce(v_state.data->'specialRecords','[]'::jsonb);v_lines:=public.seika_inventory_count_v124_section_rows(v_session,p_section);
 if coalesce(v_session->>'isTest','false')<>'true' and p_section in ('normal','kataoka') then for v_line in select value from jsonb_array_elements(v_lines) loop if coalesce(v_line->>'type','')='special' then v_special:=v_special||jsonb_build_array(v_line||jsonb_build_object('id',extensions.gen_random_uuid()::text,'qty',(v_line->>'actualQty')::numeric,'kind','棚卸し確定','stocktakeSessionId',p_session_id,'stocktakeLineId',v_line->>'lineId','operationId',p_operation_id,'createdAt',v_now,'user',coalesce(v_profile.display_name,''),'role',v_profile.role));else v_records:=v_records||jsonb_build_array(v_line||jsonb_build_object('id',extensions.gen_random_uuid()::text,'total',(v_line->>'actualQty')::numeric,'kind','棚卸し確定','stocktakeSessionId',p_session_id,'stocktakeLineId',v_line->>'lineId','operationId',p_operation_id,'createdAt',v_now,'user',coalesce(v_profile.display_name,''),'role',v_profile.role));end if;end loop;end if;
 v_new:=v_session||jsonb_build_object(v_status,'confirmed',v_key,v_revision+1,case p_section when 'normal' then 'normalConfirmedAt' when 'qr' then 'qrConfirmedAt' else 'kataokaConfirmedAt' end,v_now,case p_section when 'normal' then 'normalConfirmedBy' when 'qr' then 'qrConfirmedBy' else 'kataokaConfirmedBy' end,coalesce(v_profile.display_name,''),'status',public.seika_inventory_count_v124_status(v_session||jsonb_build_object(v_status,'confirmed')),'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1,'v124OperationIds',public.seika_inventory_count_v124_trim_operations(coalesce(v_session->'v124OperationIds','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',p_operation_id,'section',p_section,'action','confirm','at',v_now))));if public.seika_inventory_count_v124_status(v_new) in ('confirmed','test_confirmed') then v_new:=v_new||jsonb_build_object('priceStatus','waiting_price','confirmedAt',v_now,'confirmedBy',coalesce(v_profile.display_name,''));end if;v_data:=jsonb_set(v_state.data,'{records}',v_records,true);v_data:=jsonb_set(v_data,'{specialRecords}',v_special,true);v_data:=public.seika_inventory_count_v123_replace_session(v_data,p_session_id,v_new);v_data:=public.seika_inventory_count_v123_append_log(v_data,jsonb_build_object('id',extensions.gen_random_uuid()::text,'type','棚卸し','action','工程確定','section',p_section,'sessionId',p_session_id,'operationId',p_operation_id,'user',coalesce(v_profile.display_name,''),'userId',v_profile.id,'role',v_profile.role,'createdAt',v_now));update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=p_id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'sectionRevision',v_revision+1,'status',v_new->>'status','inventory_applied',coalesce(v_session->>'isTest','false')<>'true' and p_section<>'qr');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v124_mark_inventory_count_excel_export(p_id text, p_expected_version bigint, p_session_ids jsonb, p_file_name text, p_stage text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_data jsonb;v_session jsonb;v_id text;v_version bigint;v_file text:=left(btrim(coalesce(p_file_name,'')),240);v_any boolean:=false;
begin
 if p_id<>'ishioka_inventory_production_v2' or jsonb_typeof(p_session_ids)<>'array' or jsonb_array_length(p_session_ids) not between 1 and 2 or p_stage not in ('quantity','priced') or v_file='' then raise exception 'Excel出力引数が不正です' using errcode='22023';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','worker','sales','clerk') then raise exception 'Excelを出力する権限がありません' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found or v_state.version<>p_expected_version then return jsonb_build_object('ok',false,'conflict',true,'message','別端末で更新されています');end if;v_data:=v_state.data;
 for v_id in select jsonb_array_elements_text(p_session_ids) loop select value into v_session from jsonb_array_elements(coalesce(v_data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=v_id limit 1;if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002';end if;v_session:=public.seika_inventory_count_normalize_session_v124(v_session);if v_session->>'normalStatus'<>'confirmed' and v_session->>'qrCountStatus'<>'confirmed' then raise exception '確定済み工程がある棚卸しだけExcelを出力できます' using errcode='22023';end if;if p_stage='priced' and (coalesce(v_session->>'priceStatus','')<>'priced' or not public.seika_inventory_count_v124_prices_complete(v_session)) then raise exception '単価・金額確定版は全工程の単価入力後だけ出力できます' using errcode='22023';end if;v_any:=true;v_session:=v_session||jsonb_build_object('excelExportedAt',now(),'excelExportedBy',coalesce(v_profile.display_name,''),'excelExportedById',v_profile.id,'excelFileName',v_file,'excelExportStage',p_stage);v_data:=public.seika_inventory_count_v123_replace_session(v_data,v_id,v_session);end loop;
 if not v_any then raise exception 'Excel出力対象がありません' using errcode='22023';end if;update public.app_state set data=v_data,version=version+1,updated_at=now() where id=p_id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v124_purge_inventory_count_details(p_id text, p_expected_version bigint, p_session_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_data jsonb;v_version bigint;v_confirmed timestamptz;v_normal integer;v_qr integer;v_kataoka integer;v_audit jsonb;
begin
 if p_id<>'ishioka_inventory_production_v2' then raise exception '棚卸し状態IDが不正です' using errcode='22023';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role<>'admin' then raise exception '棚卸し明細を削除できるのは管理者のみです' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found or v_state.version<>p_expected_version then return jsonb_build_object('ok',false,'conflict',true,'message','別端末で更新されています');end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id limit 1;v_session:=public.seika_inventory_count_normalize_session_v124(v_session);if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002';end if;if coalesce(v_session->>'isTest','false')='true' then raise exception 'テスト棚卸しは明細削除対象外です' using errcode='22023';end if;if v_session->>'status'<>'confirmed' or coalesce(v_session->>'priceStatus','')<>'priced' or not public.seika_inventory_count_v124_prices_complete(v_session) or coalesce(v_session->>'excelExportedAt','')='' or coalesce(v_session->>'documentSavedAt','')='' then raise exception '全工程確定・単価入力・Excel出力・文書管理保存確認が完了した棚卸しだけ削除できます' using errcode='22023';end if;v_confirmed:=nullif(v_session->>'confirmedAt','')::timestamptz;if v_confirmed is null or now()<v_confirmed+interval '3 months' then raise exception '確定から3か月経過後に削除できます' using errcode='22023';end if;if coalesce(v_session->>'detailsDeletedAt','')<>'' then return jsonb_build_object('ok',true,'already_deleted',true,'version',v_state.version);end if;
 v_normal:=jsonb_array_length(coalesce(v_session->'lines','[]'::jsonb));v_qr:=jsonb_array_length(coalesce(v_session->'qrLines','[]'::jsonb));v_kataoka:=jsonb_array_length(coalesce(v_session->'kataokaLines','[]'::jsonb));v_new:=v_session||jsonb_build_object('lines','[]'::jsonb,'qrLines','[]'::jsonb,'kataokaLines','[]'::jsonb,'detailsDeletedAt',now(),'detailsDeletedBy',coalesce(v_profile.display_name,''),'detailsDeletedById',v_profile.id,'deletedNormalLineCount',v_normal,'deletedQrLineCount',v_qr,'deletedKataokaLineCount',v_kataoka,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1);v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);v_audit:=jsonb_build_object('id',extensions.gen_random_uuid()::text,'type','棚卸し','action','明細削除','sessionId',p_session_id,'user',coalesce(v_profile.display_name,''),'userId',v_profile.id,'role',v_profile.role,'detail',format('通常 %s件 / QR %s件 / 片岡 %s件を3か月保持後に削除',v_normal,v_qr,v_kataoka),'createdAt',now());v_data:=public.seika_inventory_count_v123_append_log(v_data,v_audit);update public.app_state set data=v_data,version=version+1,updated_at=now() where id=p_id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'deleted_normal_line_count',v_normal,'deleted_qr_line_count',v_qr,'deleted_kataoka_line_count',v_kataoka);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v124_return_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_data jsonb;v_key text;v_status text;v_revision bigint;v_version bigint;
begin
 if p_id<>'ishioka_inventory_production_v2' or p_section not in ('normal','qr','kataoka') or nullif(btrim(p_operation_id),'') is null then raise exception '差戻し引数が不正です' using errcode='22023';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role<>'admin' then raise exception '差戻しできるのは管理者のみです' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません';end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id;v_session:=public.seika_inventory_count_normalize_session_v124(v_session);v_key:=case p_section when 'normal' then 'normalRevision' when 'qr' then 'qrRevision' else 'kataokaRevision' end;v_status:=case p_section when 'normal' then 'normalStatus' when 'qr' then 'qrCountStatus' else 'kataokaStatus' end;v_revision:=coalesce((v_session->>v_key)::bigint,0);if p_expected_section_revision<>v_revision then return jsonb_build_object('ok',false,'conflict',true,'message','別端末で更新されています');end if;if v_session->>v_status<>'submitted' then raise exception '提出済み工程だけ差戻しできます' using errcode='22023';end if;v_new:=v_session||jsonb_build_object(v_status,'incomplete',v_key,v_revision+1,'status',public.seika_inventory_count_v124_status(v_session||jsonb_build_object(v_status,'incomplete')),'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''));v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);update public.app_state set data=v_data,version=version+1,updated_at=now()where id=p_id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'sectionRevision',v_revision+1);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v124_save_inventory_count_prices(p_id text, p_expected_version bigint, p_session_id text, p_prices jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_new jsonb;v_data jsonb;v_section text;v_rows jsonb;v_out jsonb;v_line jsonb;v_input jsonb;v_id text;v_is_qr boolean;v_actual numeric;v_price numeric;v_kg numeric;v_amount numeric;v_seen text[]:='{}';v_total numeric:=0;v_count integer:=0;v_version bigint;
begin
 if p_id<>'ishioka_inventory_production_v2' or jsonb_typeof(p_prices)<>'array' then raise exception '単価入力の引数が不正です' using errcode='22023';end if;select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','sales','clerk') then raise exception '単価を保存できるのは管理者・営業・事務です' using errcode='42501';end if;select * into v_state from public.app_state where id=p_id for update;if not found or v_state.version<>p_expected_version then return jsonb_build_object('ok',false,'conflict',true,'message','別端末で更新されています');end if;select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb))where value->>'id'=p_session_id;v_session:=public.seika_inventory_count_normalize_session_v124(v_session);if v_session is null then raise exception '棚卸しセッションが見つかりません';end if;
 for v_section in select unnest(case when v_session->>'room'='room2' then array['normal','qr','kataoka'] else array['normal','qr'] end) loop
  if (case v_section when 'normal' then v_session->>'normalStatus' when 'qr' then v_session->>'qrCountStatus' else v_session->>'kataokaStatus' end) <> 'confirmed' then continue;end if;v_rows:=public.seika_inventory_count_v124_section_rows(v_session,v_section);v_out:='[]'::jsonb;
  for v_line in select value from jsonb_array_elements(v_rows) loop v_is_qr:=v_section='qr';v_id:=case when v_is_qr then coalesce(v_line->>'qrKey',v_line->>'qr_key') else v_line->>'lineId' end;if v_id is null or v_id=any(v_seen) then raise exception '単価対象明細IDが不正または重複しています' using errcode='22023';end if;v_seen:=array_append(v_seen,v_id);select value into v_input from jsonb_array_elements(p_prices) x where(case when v_is_qr then x->>'qrKey' else x->>'lineId' end)=v_id;if (select count(*) from jsonb_array_elements(p_prices) x where(case when v_is_qr then x->>'qrKey' else x->>'lineId' end)=v_id)<>1 then raise exception '単価行が不足または重複しています' using errcode='22023';end if;v_actual:=public.seika_inventory_count_decimal_optional_v123(v_line->>'actualQty','実数');if v_actual=0 then v_price:=null;v_kg:=0;v_amount:=0;else v_price:=public.seika_inventory_count_decimal_optional_v123(v_input->>'unitPriceYenPerKg','単価');if v_price is null or v_price<0 then raise exception '%：単価は0以上で入力してください',coalesce(v_line->>'itemName','品名');end if;v_kg:=public.seika_inventory_count_line_kg_v1119(v_line,v_is_qr);if v_kg is null or v_kg<=0 then raise exception '%：kg換算を確認してください',coalesce(v_line->>'itemName','品名');end if;v_amount:=round(v_kg*v_price,0);end if;v_out:=v_out||jsonb_build_array(v_line||jsonb_build_object('unitPriceYenPerKg',v_price,'countedKg',v_kg,'amountYen',v_amount));v_total:=v_total+v_amount;v_count:=v_count+1;end loop;v_new:=v_session||jsonb_build_object(case v_section when 'normal' then 'lines' when 'qr' then 'qrLines' else 'kataokaLines' end,v_out);
  v_session:=v_new;
 end loop;
 if v_count=0 then raise exception '確定済みの単価対象工程がありません' using errcode='22023';end if;v_new:=v_session||jsonb_build_object('priceStatus','priced','pricedAt',now(),'pricedBy',coalesce(v_profile.display_name,''),'pricedById',v_profile.id,'priceTotalYen',v_total,'priceLineCount',v_count,'updatedAt',now(),'updatedBy',coalesce(v_profile.display_name,''),'revision',coalesce((v_session->>'revision')::bigint,0)+1);v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);update public.app_state set data=v_data,version=version+1,updated_at=now()where id=p_id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'line_count',v_count,'total_amount_yen',v_total);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v124_save_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint, p_entries jsonb, p_action text, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_source jsonb;v_entry jsonb;v_rows jsonb:='[]'::jsonb;v_new jsonb;v_data jsonb;v_revision bigint;v_id text;v_revision_key text;v_status_key text;v_rows_key text;v_prefix text;v_actual numeric;v_weight numeric;v_kg numeric;v_remainder numeric;v_sum numeric;v_active boolean;v_weight_entries jsonb;v_weight_entry jsonb;v_missing integer:=0;v_count integer;v_version bigint;v_now timestamptz:=now();v_is_kg boolean;
begin
 if p_id<>'ishioka_inventory_production_v2' or p_section not in ('normal','qr','kataoka') or p_action not in ('draft','submit') or jsonb_typeof(p_entries)<>'array' or nullif(btrim(p_session_id),'') is null or nullif(btrim(p_operation_id),'') is null or char_length(p_operation_id)>200 then raise exception '棚卸し保存の引数が不正です' using errcode='22023';end if;
 select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','worker') then raise exception '棚卸しを保存できるのは管理者・青果社員です' using errcode='42501';end if;
 select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002';end if;
 select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id limit 1;if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002';end if;
 v_session:=public.seika_inventory_count_normalize_session_v124(v_session);
 if p_section='kataoka' and (v_session->>'room'<>'room2' or v_session->>'normalStatus' not in ('submitted','confirmed')) then raise exception '片岡在庫は第2冷蔵庫の通常在庫提出後に入力できます' using errcode='22023';end if;
 v_revision_key:=case p_section when 'normal' then 'normalRevision' when 'qr' then 'qrRevision' else 'kataokaRevision' end;v_status_key:=case p_section when 'normal' then 'normalStatus' when 'qr' then 'qrCountStatus' else 'kataokaStatus' end;v_rows_key:=case p_section when 'normal' then 'lines' when 'qr' then 'qrLines' else 'kataokaLines' end;v_prefix:=case p_section when 'normal' then 'normal' when 'qr' then 'qr' else 'kataoka' end;
 if exists(select 1 from jsonb_array_elements(coalesce(v_session->'v124OperationIds','[]'::jsonb)) x where x->>'id'=p_operation_id) then return jsonb_build_object('ok',true,'idempotent',true,'version',v_state.version,'sectionRevision',coalesce((v_session->>v_revision_key)::bigint,0));end if;
 v_revision:=coalesce((v_session->>v_revision_key)::bigint,0);if p_expected_section_revision is null or p_expected_section_revision<>v_revision then return jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'sectionRevision',v_revision,'message','別端末で更新されています。');end if;
 if v_session->>v_status_key='confirmed' then raise exception '確定済み工程は変更できません' using errcode='22023';end if;
 if jsonb_array_length(p_entries)<>jsonb_array_length(public.seika_inventory_count_v124_section_rows(v_session,p_section)) then raise exception '入力件数が棚卸し対象と一致しません' using errcode='22023';end if;
 for v_source in select value from jsonb_array_elements(public.seika_inventory_count_v124_section_rows(v_session,p_section)) loop
  v_id:=case when p_section='qr' then nullif(btrim(coalesce(v_source->>'qrKey',v_source->>'qr_key')),'') else nullif(btrim(v_source->>'lineId'),'') end;if v_id is null then raise exception '棚卸し明細IDが不正です' using errcode='22023';end if;
  select count(*) into v_count from jsonb_array_elements(p_entries) x where nullif(btrim(x->>'id'),'')=v_id;if v_count<>1 then raise exception '入力明細が不足または重複しています' using errcode='22023';end if;
  select value into v_entry from jsonb_array_elements(p_entries) x where nullif(btrim(x->>'id'),'')=v_id limit 1;
  v_is_kg:=p_section<>'qr' and (lower(coalesce(v_source->>'unit','kg'))='kg' or coalesce(v_source->>'type','')='normal');
  if v_is_kg then
   if jsonb_typeof(v_entry->'weightEntries')<>'array' or jsonb_array_length(v_entry->'weightEntries') not between 1 and 20 then raise exception '%：量目明細は1〜20行で入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
   v_sum:=0;v_active:=false;v_weight_entries:='[]'::jsonb;
   for v_weight_entry in select value from jsonb_array_elements(v_entry->'weightEntries') loop
    v_kg:=public.seika_inventory_count_decimal_optional_v123(v_weight_entry->>'packKg','量目kg');v_weight:=public.seika_inventory_count_decimal_optional_v123(v_weight_entry->>'caseCount','ケース数');
    if nullif(btrim(coalesce(v_weight_entry->>'packKg','')),'') is not null or nullif(btrim(coalesce(v_weight_entry->>'caseCount','')),'') is not null then
     if v_kg is null or v_kg<=0 or v_weight is null or v_weight<0 then raise exception '%：量目kgは0より大きく、ケース数は0以上で入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
     v_sum:=v_sum+v_kg*v_weight;v_active:=true;
    end if;v_weight_entries:=v_weight_entries||jsonb_build_array(jsonb_build_object('id',left(coalesce(v_weight_entry->>'id',''),100),'packKg',coalesce(v_kg::text,''),'caseCount',coalesce(v_weight::text,'')));
   end loop;
   v_remainder:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'remainderKg','端数kg');if v_remainder is not null and v_remainder<0 then raise exception '%：端数kgは0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if v_remainder is not null then v_sum:=v_sum+v_remainder;v_active:=true;end if;v_actual:=case when v_active then round(v_sum,3) else null end;
   if p_action='submit' and coalesce((v_entry->>'supplierRequired')::boolean,false) and btrim(coalesce(v_entry->>'supplier',''))='' then raise exception '%：仕入先を入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
   v_source:=v_source||jsonb_build_object('weightEntries',v_weight_entries,'remainderKg',coalesce(v_remainder::text,''),'inputMode','weight_entries','actualQty',v_actual,'supplier',left(btrim(coalesce(v_entry->>'supplier','')),160),'supplierRequired',coalesce((v_entry->>'supplierRequired')::boolean,false),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000));
  elsif p_section='qr' then
   v_actual:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty','実数');if v_actual is not null and v_actual<0 then raise exception '%：実数は0以上です',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;v_weight:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualWeightKg','棚卸し重量kg');if v_weight is not null and v_weight<0 then raise exception '%：棚卸し重量kgは0以上です',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;if p_action='submit' and coalesce(v_source->>'unit','')='基' and v_actual is not null and v_weight is null and (coalesce((v_source->>'snapshotTotalWeight')::numeric,0)<=0 or coalesce((v_source->>'snapshotInitialQty')::numeric,0)<=0) then raise exception '%：大型容器は棚卸し重量kgを入力してください',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;
   v_source:=v_source||jsonb_build_object('actualQty',v_actual,'actualWeightKg',v_weight,'outQty',coalesce(public.seika_inventory_count_decimal_optional_v123(v_entry->>'outQty','簡単出庫'),0),'destination',left(btrim(coalesce(v_entry->>'destination','')),160),'shipTiming',left(btrim(coalesce(v_entry->>'shipTiming','')),80),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000));
  else
   v_actual:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty','実数');if v_actual is not null and v_actual<0 then raise exception '%：実数は0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;v_kg:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'kgPerUnit','1単位あたりkg');if v_kg is not null and v_kg<=0 then raise exception '%：1単位あたりkgは0より大きい値です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if p_action='submit' and coalesce((v_entry->>'supplierRequired')::boolean,false) and btrim(coalesce(v_entry->>'supplier',''))='' then raise exception '%：仕入先を入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
   v_source:=v_source||jsonb_build_object('actualQty',v_actual,'kgPerUnit',coalesce(v_kg::text,''),'supplier',left(btrim(coalesce(v_entry->>'supplier','')),160),'supplierRequired',coalesce((v_entry->>'supplierRequired')::boolean,false),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000));
  end if;
  if (v_source->>'actualQty') is null or v_source->>'actualQty'='' then v_missing:=v_missing+1;end if;v_rows:=v_rows||jsonb_build_array(v_source||jsonb_build_object('status',case when (v_source->>'actualQty') is null then 'unentered' else 'entered' end));
 end loop;
 if p_action='submit' and v_missing>0 then raise exception '未入力が%件あります。未入力のまま保存する場合は下書き保存を選んでください',v_missing using errcode='22023';end if;
 v_new:=v_session||jsonb_build_object(v_rows_key,v_rows,v_status_key,case when p_action='submit' then 'submitted' when v_missing>0 then 'incomplete' else 'counting' end,v_revision_key,v_revision+1,format('%sSavedAt',v_prefix),v_now,format('%sSavedBy',v_prefix),coalesce(v_profile.display_name,''),format('%sSavedById',v_prefix),v_profile.id,format('%sSubmittedAt',v_prefix),case when p_action='submit' then v_now else null end,format('%sSubmittedBy',v_prefix),case when p_action='submit' then coalesce(v_profile.display_name,'') else null end,format('%sSubmittedById',v_prefix),case when p_action='submit' then v_profile.id else null end);
 v_new:=v_new||jsonb_build_object('status',public.seika_inventory_count_v124_status(v_new),'revision',coalesce((v_session->>'revision')::bigint,0)+1,'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'v124OperationIds',public.seika_inventory_count_v124_trim_operations(coalesce(v_session->'v124OperationIds','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',p_operation_id,'section',p_section,'action',p_action,'at',v_now))));
 v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);v_data:=public.seika_inventory_count_v123_append_log(v_data,jsonb_build_object('id',extensions.gen_random_uuid()::text,'type','棚卸し','action',case when p_action='submit' then '工程入力完了' else '工程下書き保存' end,'section',p_section,'sessionId',p_session_id,'user',coalesce(v_profile.display_name,''),'userId',v_profile.id,'role',v_profile.role,'operationId',p_operation_id,'createdAt',v_now));update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'sectionRevision',v_revision+1,'missing',v_missing,'status',v_new->>'status');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v171_complete_simple_inventory_count_session(p_id text, p_session_id text, p_expected_session_revision bigint, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_session jsonb;
  v_new jsonb;
  v_data jsonb;
  v_version bigint;
  v_revision bigint;
  v_section text;
  v_sections text[];
  v_status text;
  v_now timestamptz := now();
begin
  if p_id <> 'ishioka_inventory_production_v2' or nullif(btrim(p_session_id),'') is null or nullif(btrim(p_operation_id),'') is null or char_length(p_operation_id) > 200 or p_expected_session_revision is null then
    raise exception '簡易棚卸し完了の引数が不正です' using errcode='22023';
  end if;
  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin','worker') then raise exception '棚卸しを完了できるのは管理者・青果社員のみです' using errcode='42501'; end if;
  select * into v_state from public.app_state where id=p_id for update;
  if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002'; end if;
  select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id limit 1;
  if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002'; end if;
  v_session:=public.seika_inventory_count_normalize_session_v124(v_session);
  if coalesce(v_session->>'inventoryCountMode','') <> 'simple_v171' then raise exception 'v1.172簡易棚卸し以外は完了できません' using errcode='22023'; end if;
  v_revision:=coalesce((v_session->>'revision')::bigint,0);
  if nullif(v_session->>'v171CompletedAt','') is not null then
    return jsonb_build_object('ok',true,'idempotent',true,'completed',true,'version',v_state.version,'sessionRevision',v_revision,'status','completed');
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(v_session->'v171OperationIds','[]'::jsonb)) operation where operation->>'id'=p_operation_id) then
    return jsonb_build_object('ok',true,'idempotent',true,'completed',false,'version',v_state.version,'sessionRevision',v_revision,'status',coalesce(v_session->>'status',''));
  end if;
  if p_expected_session_revision <> v_revision then
    return jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'sessionRevision',v_revision,'message','別端末で更新されています。最新データを読み込んでください。');
  end if;
  v_sections:=case when v_session->>'room'='room2' then array['normal','qr','kataoka'] when v_session->>'room'='room3' then array['normal','qr'] else null end;
  if v_sections is null then raise exception '棚卸し冷蔵庫が不正です' using errcode='22023'; end if;
  foreach v_section in array v_sections loop
    v_status:=case v_section when 'normal' then coalesce(v_session->>'normalStatus','counting') when 'qr' then coalesce(v_session->>'qrCountStatus','counting') else coalesce(v_session->>'kataokaStatus','counting') end;
    if v_status <> 'submitted' then
      return jsonb_build_object('ok',true,'completed',false,'version',v_state.version,'sessionRevision',v_revision,'status',coalesce(v_session->>'status',''),'message','すべての工程を入力完了として保存してから完了になります。');
    end if;
  end loop;
  v_new:=v_session||jsonb_build_object(
    'status','completed','v171CompletedAt',v_now,'v171CompletedBy',coalesce(v_profile.display_name,''),'v171CompletedById',v_profile.id,'v171CompletedOperationId',p_operation_id,
    'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'revision',v_revision+1,
    'v171OperationIds',public.seika_inventory_count_v124_trim_operations(coalesce(v_session->'v171OperationIds','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',p_operation_id,'action','v171_complete','at',v_now)))
  );
  v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);
  update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;
  return jsonb_build_object('ok',true,'completed',true,'version',v_version,'sessionRevision',v_revision+1,'status','completed','inventory_applied',false,'qr_applied',false);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v171_create_simple_inventory_count_session(p_id text, p_session jsonb, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_profile public.profiles%rowtype;
 v_state public.app_state%rowtype;
 v_session jsonb;
 v_data jsonb;
 v_version bigint;
 v_now timestamptz:=now();
 v_existing jsonb;
 v_active jsonb;
begin
 if p_id<>'ishioka_inventory_production_v2'
    or jsonb_typeof(p_session)<>'object'
    or nullif(btrim(p_session->>'id'),'') is null
    or char_length(p_session->>'id')>200
    or nullif(btrim(p_session->>'countNo'),'') is null
    or p_session->>'room' not in ('room2','room3')
    or p_session->>'inventoryCountMode'<>'simple_v171'
    or jsonb_typeof(coalesce(p_session->'lines','[]'::jsonb))<>'array'
    or jsonb_typeof(coalesce(p_session->'qrLines','[]'::jsonb))<>'array'
    or nullif(btrim(p_operation_id),'') is null
    or char_length(p_operation_id)>200
 then raise exception '簡易棚卸し開始データが不正です' using errcode='22023'; end if;
 select * into v_profile from public.seika_inventory_count_profile_v123();
 if not found or v_profile.role not in ('admin','worker') then raise exception '棚卸し開始は管理者・青果社員のみです' using errcode='42501'; end if;
 select * into v_state from public.app_state where id=p_id for update;
 if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002'; end if;
 select value into v_existing
 from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb))
 where value->>'id'=p_session->>'id' limit 1;
 if v_existing is not null then
   return jsonb_build_object('ok',true,'idempotent',true,'version',v_state.version,'session_id',v_existing->>'id');
 end if;
 if exists (
   select 1 from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) s,
                 jsonb_array_elements(coalesce(s.value->'v171OperationIds','[]'::jsonb)) o
   where o->>'id'=p_operation_id
 ) then raise exception 'この操作IDは別の棚卸しで使用されています' using errcode='23505'; end if;
 select value into v_active
 from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb))
 where value->>'room'=p_session->>'room'
   and coalesce(value->>'status','') not in ('completed','confirmed','test_confirmed','reversed','cancelled')
 limit 1;
 if v_active is not null then
   if coalesce(v_active->>'inventoryCountMode','')='simple_v171' then
     raise exception 'この冷蔵庫には進行中の簡易棚卸しがあります' using errcode='23505';
   end if;
   raise exception 'この冷蔵庫には進行中の旧棚卸しがあります。旧棚卸しは閲覧専用のため、新規開始できません' using errcode='23505';
 end if;
 v_session:=public.seika_inventory_count_normalize_session_v124(
   p_session||jsonb_build_object(
     'inventoryCountMode','simple_v171',
     'startedAt',coalesce(p_session->>'startedAt',v_now::text),
     'startedBy',coalesce(v_profile.display_name,''),
     'startedById',v_profile.id,
     'updatedAt',v_now,
     'updatedBy',coalesce(v_profile.display_name,''),
     'revision',1,
     'v171OperationIds',jsonb_build_array(jsonb_build_object('id',p_operation_id,'action','create','at',v_now))
   )
 );
 v_data:=jsonb_set(v_state.data,'{inventoryCounts,sessions}',coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)||jsonb_build_array(v_session),true);
 update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;
 return jsonb_build_object('ok',true,'version',v_version,'session_id',v_session->>'id','normalRevision',coalesce((v_session->>'normalRevision')::bigint,0),'qrRevision',coalesce((v_session->>'qrRevision')::bigint,0));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v171_save_simple_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint, p_entries jsonb, p_action text, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.profiles%rowtype;v_state public.app_state%rowtype;v_session jsonb;v_source jsonb;v_entry jsonb;v_rows jsonb:='[]'::jsonb;v_new jsonb;v_data jsonb;v_revision bigint;v_id text;v_revision_key text;v_status_key text;v_rows_key text;v_prefix text;v_actual numeric;v_weight numeric;v_kg numeric;v_remainder numeric;v_sum numeric;v_active boolean;v_weight_entries jsonb;v_weight_entry jsonb;v_missing integer:=0;v_count integer;v_version bigint;v_now timestamptz:=now();v_is_kg boolean;
begin
 if p_id<>'ishioka_inventory_production_v2' or p_section not in ('normal','qr','kataoka') or p_action not in ('draft','submit') or jsonb_typeof(p_entries)<>'array' or nullif(btrim(p_session_id),'') is null or nullif(btrim(p_operation_id),'') is null or char_length(p_operation_id)>200 then raise exception '棚卸し保存の引数が不正です' using errcode='22023';end if;
 select * into v_profile from public.seika_inventory_count_profile_v123();if not found or v_profile.role not in ('admin','worker') then raise exception '棚卸しを保存できるのは管理者・青果社員です' using errcode='42501';end if;
 select * into v_state from public.app_state where id=p_id for update;if not found then raise exception '棚卸し状態が見つかりません' using errcode='P0002';end if;
 select value into v_session from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) where value->>'id'=p_session_id limit 1;if v_session is null then raise exception '棚卸しセッションが見つかりません' using errcode='P0002';end if;
 v_session:=public.seika_inventory_count_normalize_session_v124(v_session);if coalesce(v_session->>'inventoryCountMode','')<>'simple_v171' then raise exception '旧棚卸しは閲覧専用です' using errcode='22023';end if;if nullif(v_session->>'v171CompletedAt','') is not null or coalesce(v_session->>'status','')='completed' then raise exception '完了済みの簡易棚卸しは編集できません' using errcode='22023';end if;
 if p_section='kataoka' and (v_session->>'room'<>'room2' or v_session->>'normalStatus' not in ('submitted','confirmed')) then raise exception '片岡在庫は第2冷蔵庫の通常在庫提出後に入力できます' using errcode='22023';end if;
 v_revision_key:=case p_section when 'normal' then 'normalRevision' when 'qr' then 'qrRevision' else 'kataokaRevision' end;v_status_key:=case p_section when 'normal' then 'normalStatus' when 'qr' then 'qrCountStatus' else 'kataokaStatus' end;v_rows_key:=case p_section when 'normal' then 'lines' when 'qr' then 'qrLines' else 'kataokaLines' end;v_prefix:=case p_section when 'normal' then 'normal' when 'qr' then 'qr' else 'kataoka' end;
 if exists(select 1 from jsonb_array_elements(coalesce(v_session->'v171OperationIds','[]'::jsonb)) x where x->>'id'=p_operation_id) then return jsonb_build_object('ok',true,'idempotent',true,'version',v_state.version,'sectionRevision',coalesce((v_session->>v_revision_key)::bigint,0));end if;
 v_revision:=coalesce((v_session->>v_revision_key)::bigint,0);if p_expected_section_revision is null or p_expected_section_revision<>v_revision then return jsonb_build_object('ok',false,'conflict',true,'version',v_state.version,'sectionRevision',v_revision,'message','別端末で更新されています。');end if;
 if v_session->>v_status_key='confirmed' then raise exception '確定済み工程は変更できません' using errcode='22023';end if;
 if jsonb_array_length(p_entries)<>jsonb_array_length(public.seika_inventory_count_v124_section_rows(v_session,p_section)) then raise exception '入力件数が棚卸し対象と一致しません' using errcode='22023';end if;
 for v_source in select value from jsonb_array_elements(public.seika_inventory_count_v124_section_rows(v_session,p_section)) loop
  v_id:=case when p_section='qr' then nullif(btrim(coalesce(v_source->>'qrKey',v_source->>'qr_key')),'') else nullif(btrim(v_source->>'lineId'),'') end;if v_id is null then raise exception '棚卸し明細IDが不正です' using errcode='22023';end if;
  select count(*) into v_count from jsonb_array_elements(p_entries) x where nullif(btrim(x->>'id'),'')=v_id;if v_count<>1 then raise exception '入力明細が不足または重複しています' using errcode='22023';end if;
  select value into v_entry from jsonb_array_elements(p_entries) x where nullif(btrim(x->>'id'),'')=v_id limit 1;
  v_is_kg:=p_section<>'qr' and (lower(coalesce(v_source->>'unit','kg'))='kg' or coalesce(v_source->>'type','')='normal');
  if v_is_kg then
   if jsonb_typeof(v_entry->'weightEntries')<>'array' or jsonb_array_length(v_entry->'weightEntries') not between 1 and 20 then raise exception '%：量目明細は1〜20行で入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
   v_sum:=0;v_active:=false;v_weight_entries:='[]'::jsonb;
   for v_weight_entry in select value from jsonb_array_elements(v_entry->'weightEntries') loop
    v_kg:=public.seika_inventory_count_decimal_optional_v123(v_weight_entry->>'packKg','量目kg');v_weight:=public.seika_inventory_count_decimal_optional_v123(v_weight_entry->>'caseCount','ケース数');
    if nullif(btrim(coalesce(v_weight_entry->>'packKg','')),'') is not null or nullif(btrim(coalesce(v_weight_entry->>'caseCount','')),'') is not null then
     if v_kg is null or v_kg<=0 or v_weight is null or v_weight<0 then raise exception '%：量目kgは0より大きく、ケース数は0以上で入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
     v_sum:=v_sum+v_kg*v_weight;v_active:=true;
    end if;v_weight_entries:=v_weight_entries||jsonb_build_array(jsonb_build_object('id',left(coalesce(v_weight_entry->>'id',''),100),'packKg',coalesce(v_kg::text,''),'caseCount',coalesce(v_weight::text,'')));
   end loop;
   v_remainder:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'remainderKg','端数kg');if v_remainder is not null and v_remainder<0 then raise exception '%：端数kgは0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if v_remainder is not null then v_sum:=v_sum+v_remainder;v_active:=true;end if;v_actual:=case when v_active then round(v_sum,3) else null end;
   if p_action='submit' and coalesce((v_entry->>'supplierRequired')::boolean,false) and btrim(coalesce(v_entry->>'supplier',''))='' then raise exception '%：仕入先を入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
   v_source:=v_source||jsonb_build_object('weightEntries',v_weight_entries,'remainderKg',coalesce(v_remainder::text,''),'inputMode','weight_entries','actualQty',v_actual,'supplier',left(btrim(coalesce(v_entry->>'supplier','')),160),'supplierRequired',coalesce((v_entry->>'supplierRequired')::boolean,false),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000));
  elsif p_section='qr' then
   v_actual:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty','実数');if v_actual is not null and v_actual<0 then raise exception '%：実数は0以上です',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;v_weight:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualWeightKg','棚卸し重量kg');if v_weight is not null and v_weight<0 then raise exception '%：棚卸し重量kgは0以上です',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;if p_action='submit' and coalesce(v_source->>'unit','')='基' and v_actual is not null and v_weight is null and (coalesce((v_source->>'snapshotTotalWeight')::numeric,0)<=0 or coalesce((v_source->>'snapshotInitialQty')::numeric,0)<=0) then raise exception '%：大型容器は棚卸し重量kgを入力してください',coalesce(v_source->>'itemName','QRロット') using errcode='22023';end if;
   v_source:=v_source||jsonb_build_object('actualQty',v_actual,'actualWeightKg',v_weight,'outQty',coalesce(public.seika_inventory_count_decimal_optional_v123(v_entry->>'outQty','簡単出庫'),0),'destination',left(btrim(coalesce(v_entry->>'destination','')),160),'shipTiming',left(btrim(coalesce(v_entry->>'shipTiming','')),80),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000));
  else
   v_actual:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty','実数');if v_actual is not null and v_actual<0 then raise exception '%：実数は0以上です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;v_kg:=public.seika_inventory_count_decimal_optional_v123(v_entry->>'kgPerUnit','1単位あたりkg');if v_kg is not null and v_kg<=0 then raise exception '%：1単位あたりkgは0より大きい値です',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;if p_action='submit' and coalesce((v_entry->>'supplierRequired')::boolean,false) and btrim(coalesce(v_entry->>'supplier',''))='' then raise exception '%：仕入先を入力してください',coalesce(v_source->>'itemName','品目') using errcode='22023';end if;
   v_source:=v_source||jsonb_build_object('actualQty',v_actual,'kgPerUnit',coalesce(v_kg::text,''),'supplier',left(btrim(coalesce(v_entry->>'supplier','')),160),'supplierRequired',coalesce((v_entry->>'supplierRequired')::boolean,false),'memo',left(btrim(coalesce(v_entry->>'memo','')),1000));
  end if;
  if (v_source->>'actualQty') is null or v_source->>'actualQty'='' then v_missing:=v_missing+1;end if;v_rows:=v_rows||jsonb_build_array(v_source||jsonb_build_object('status',case when (v_source->>'actualQty') is null then 'unentered' else 'entered' end));
 end loop;
 if p_action='submit' and v_missing>0 then raise exception '未入力が%件あります。未入力のまま保存する場合は下書き保存を選んでください',v_missing using errcode='22023';end if;
 v_new:=v_session||jsonb_build_object(v_rows_key,v_rows,v_status_key,case when p_action='submit' then 'submitted' when v_missing>0 then 'incomplete' else 'counting' end,v_revision_key,v_revision+1,format('%sSavedAt',v_prefix),v_now,format('%sSavedBy',v_prefix),coalesce(v_profile.display_name,''),format('%sSavedById',v_prefix),v_profile.id,format('%sSubmittedAt',v_prefix),case when p_action='submit' then v_now else null end,format('%sSubmittedBy',v_prefix),case when p_action='submit' then coalesce(v_profile.display_name,'') else null end,format('%sSubmittedById',v_prefix),case when p_action='submit' then v_profile.id else null end);
 v_new:=v_new||jsonb_build_object('status',public.seika_inventory_count_v124_status(v_new),'revision',coalesce((v_session->>'revision')::bigint,0)+1,'updatedAt',v_now,'updatedBy',coalesce(v_profile.display_name,''),'v171OperationIds',public.seika_inventory_count_v124_trim_operations(coalesce(v_session->'v171OperationIds','[]'::jsonb)||jsonb_build_array(jsonb_build_object('id',p_operation_id,'section',p_section,'action',p_action,'at',v_now))));
 v_data:=public.seika_inventory_count_v123_replace_session(v_state.data,p_session_id,v_new);update public.app_state set data=v_data,version=version+1,updated_at=v_now where id=v_state.id returning version into v_version;return jsonb_build_object('ok',true,'version',v_version,'sectionRevision',v_revision+1,'missing',v_missing,'status',v_new->>'status');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_apply_inventory_count_session(p_id text, p_session_id text, p_expected_session_revision bigint, p_operation_id text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_session jsonb;
  v_data jsonb;
  v_new jsonb;
  v_line jsonb;
  v_latest jsonb;
  v_settings jsonb;
  v_records jsonb;
  v_movements jsonb;
  v_special_records jsonb;
  v_record_lines jsonb;
  v_weight_entry jsonb;
  v_lot public.qr_lots%rowtype;
  v_existing_movement public.qr_lot_movements%rowtype;
  v_now timestamptz := pg_catalog.now();
  v_revision bigint;
  v_current numeric;
  v_actual numeric;
  v_snapshot numeric;
  v_diff numeric;
  v_out numeric;
  v_before_weight numeric;
  v_after_weight numeric;
  v_min numeric;
  v_max numeric;
  v_status text;
  v_type text;
  v_destination text;
  v_qr_key text;
  v_hash text;
  v_qr_operation_id uuid;
  v_record_id text;
  v_normal_count integer := 0;
  v_special_count integer := 0;
  v_qr_count integer := 0;
  v_qr_decrease_count integer := 0;
  v_qr_increase_count integer := 0;
  v_qr_same_count integer := 0;
  v_result jsonb;
  v_version bigint;
begin
  if p_id <> 'ishioka_inventory_production_v2'
     or nullif(pg_catalog.btrim(p_session_id), '') is null
     or nullif(pg_catalog.btrim(p_operation_id), '') is null
     or pg_catalog.char_length(p_operation_id) > 200
     or pg_catalog.jsonb_typeof(coalesce(p_device_meta, '{}'::jsonb)) <> 'object'
     or pg_catalog.jsonb_typeof(coalesce(p_operation_meta, '{}'::jsonb)) <> 'object' then
    raise exception '棚卸し反映の引数が不正です' using errcode = '22023';
  end if;

  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin', 'worker') then
    raise exception '棚卸しを反映できるのは管理者・青果社員のみです' using errcode = '42501';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;
  select value into v_session
    from pg_catalog.jsonb_array_elements(public.v177_inventory_sessions(v_state.data))
   where value->>'id' = p_session_id
   limit 1;
  if v_session is null then
    raise exception '棚卸しセッションが見つかりません' using errcode = 'P0002';
  end if;

  /* v177 preserves its own two-section session layout. */
  if coalesce(v_session->>'inventoryCountMode', '') <> 'inventory_apply_v177' then
    raise exception '旧棚卸しは在庫反映できません' using errcode = '22023';
  end if;
  if public.v177_parse_boolean(v_session->>'v177Applied', '棚卸し反映済みフラグ', false) then
    if v_session->>'v177ApplyOperationId' = p_operation_id then
      return coalesce(v_session->'v177ApplyResult', pg_catalog.jsonb_build_object('ok', true, 'idempotent', true));
    end if;
    raise exception 'この棚卸しは既に反映済みです。別のoperation_idでは再実行できません' using errcode = '23505';
  end if;

  v_revision := coalesce(public.v177_parse_bigint(v_session->>'revision', '棚卸しリビジョン'), 0);
  if p_expected_session_revision is null or p_expected_session_revision <> v_revision then
    return pg_catalog.jsonb_build_object(
      'ok', false, 'conflict', true, 'version', v_state.version,
      'sessionRevision', v_revision, 'message', '別端末で棚卸しが更新されています。最新表示で確認してください。'
    );
  end if;

  if v_session->>'normalStatus' <> 'submitted'
     or v_session->>'qrCountStatus' <> 'submitted' then
    raise exception '通常在庫・QR在庫をそれぞれ入力完了として保存してから一括反映してください' using errcode = '22023';
  end if;

  v_data := public.v177_require_json_object(v_state.data, 'app_state.data');
  perform public.v177_inventory_sessions(v_data);
  v_records := public.v177_require_json_array(v_data->'records', 'app_state.data.records');
  v_movements := public.v177_require_json_array(v_data->'movements', 'app_state.data.movements');
  v_special_records := public.v177_require_json_array(v_data->'specialRecords', 'app_state.data.specialRecords');

  for v_line in
    select value
      from pg_catalog.jsonb_array_elements(public.v177_require_json_array(v_session->'lines', '通常在庫棚卸し明細'))
     order by value->>'lineId'
  loop
    perform public.v177_require_json_object(v_line, '通常在庫棚卸し明細');
    v_actual := public.v177_parse_decimal(v_line->>'actualQty', '通常在庫の実数');
    if v_actual is null or v_actual < 0 then
      raise exception '%：通常在庫の実数が未入力または不正です', coalesce(v_line->>'itemName', '品目') using errcode = '22023';
    end if;

    if coalesce(v_line->>'type', '') = 'normal' then
      select value into v_latest
        from pg_catalog.jsonb_array_elements(v_records)
       where value->>'itemId' = v_line->>'itemId'
       order by value->>'createdAt' desc, value->>'id' desc
       limit 1;
      if coalesce(v_latest->>'id', '') is distinct from coalesce(v_line->>'snapshotRecordId', '') then
        raise exception '%：棚卸し開始後に通常在庫が更新されています。最新在庫で棚卸しをやり直してください', coalesce(v_line->>'itemName', '品目') using errcode = '40001';
      end if;
      v_current := coalesce(public.v177_parse_decimal(v_latest->>'total', '通常在庫の帳簿数量'), 0);
      v_diff := pg_catalog.round(v_actual - v_current, 3);
      v_settings := coalesce((public.v177_require_json_object(v_data->'settings', 'app_state.data.settings'))->(v_line->>'itemId'), '{}'::jsonb);
      if pg_catalog.jsonb_typeof(v_settings) <> 'object' then
        v_settings := '{}'::jsonb;
      end if;
      v_min := public.v177_parse_decimal(v_settings->>'min', '適正在庫下限', true);
      v_max := public.v177_parse_decimal(v_settings->>'max', '適正在庫上限', true);
      v_status := case when v_min is not null and v_actual < v_min then 'shortage'
                       when v_max is not null and v_actual > v_max then 'excess'
                       else 'normal' end;
      v_record_lines := '[]'::jsonb;
      for v_weight_entry in
        select value from pg_catalog.jsonb_array_elements(public.v177_require_json_array(v_line->'weightEntries', '通常在庫の量目明細'))
      loop
        if nullif(v_weight_entry->>'packKg', '') is not null
           and nullif(v_weight_entry->>'caseCount', '') is not null then
          v_record_lines := v_record_lines || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'pack', public.v177_parse_decimal(v_weight_entry->>'packKg', '保存済み量目kg'),
            'cases', public.v177_parse_decimal(v_weight_entry->>'caseCount', '保存済みケース数'),
            'subtotal', pg_catalog.round(public.v177_parse_decimal(v_weight_entry->>'packKg', '保存済み量目kg') * public.v177_parse_decimal(v_weight_entry->>'caseCount', '保存済みケース数'), 3)
          ));
        end if;
      end loop;
      if coalesce(public.v177_parse_decimal(v_line->>'remainderKg', '保存済み端数kg'), 0) <> 0 then
        v_record_lines := v_record_lines || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'pack', 1, 'cases', public.v177_parse_decimal(v_line->>'remainderKg', '保存済み端数kg'),
          'subtotal', public.v177_parse_decimal(v_line->>'remainderKg', '保存済み端数kg'),
          'stocktakeAdjustment', true
        ));
      end if;
      if pg_catalog.jsonb_array_length(v_record_lines) = 0 then
        v_record_lines := pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('pack', 1, 'cases', v_actual, 'subtotal', v_actual, 'stocktakeAdjustment', true));
      end if;
      v_record_id := p_operation_id || ':normal:' || coalesce(v_line->>'lineId', v_line->>'itemId');
      v_records := v_records || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'id', v_record_id, 'kind', '棚卸し反映', 'itemId', v_line->>'itemId', 'itemName', v_line->>'itemName',
        'total', v_actual, 'setting', v_settings, 'status', v_status, 'lines', v_record_lines,
        'user', coalesce(v_profile.display_name, ''), 'role', v_profile.role, 'createdAt', v_now,
        'stocktakeSessionId', p_session_id, 'stocktakeLineId', v_line->>'lineId', 'operationId', p_operation_id,
        'supplier', coalesce(v_line->>'supplier', ''), 'memo', coalesce(v_line->>'memo', '')
      ));
      v_movements := v_movements || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'id', p_operation_id || ':movement:' || coalesce(v_line->>'lineId', v_line->>'itemId'),
        'recordId', v_record_id, 'itemId', v_line->>'itemId', 'itemName', v_line->>'itemName', 'type', '棚卸し調整',
        'beforeTotal', v_current, 'afterTotal', v_actual, 'diffKg', v_diff,
        'memo', '棚卸し反映 ' || coalesce(v_session->>'countNo', ''),
        'user', coalesce(v_profile.display_name, ''), 'role', v_profile.role, 'createdAt', v_now,
        'stocktakeSessionId', p_session_id, 'stocktakeLineId', v_line->>'lineId', 'operationId', p_operation_id
      ));
      v_normal_count := v_normal_count + 1;
    else
      select value into v_latest
        from pg_catalog.jsonb_array_elements(v_special_records)
       where value->>'tableId' = v_line->>'tableId'
         and value->>'itemId' = v_line->>'itemId'
       order by value->>'createdAt' desc, value->>'id' desc
       limit 1;
      if coalesce(v_latest->>'id', '') is distinct from coalesce(v_line->>'snapshotRecordId', '') then
        raise exception '%：棚卸し開始後にその他在庫が更新されています。最新在庫で棚卸しをやり直してください', coalesce(v_line->>'itemName', '品目') using errcode = '40001';
      end if;
      v_current := coalesce(public.v177_parse_decimal(v_latest->>'qty', 'その他在庫の帳簿数量'), 0);
      v_diff := pg_catalog.round(v_actual - v_current, 3);
      v_special_records := v_special_records || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'id', p_operation_id || ':special:' || coalesce(v_line->>'lineId', v_line->>'itemId'),
        'tableId', v_line->>'tableId', 'itemId', v_line->>'itemId', 'itemName', v_line->>'itemName',
        'qty', v_actual, 'unit', coalesce(v_line->>'unit', 'ケース'),
        'memo', coalesce(v_line->>'memo', ''), 'kind', '棚卸し反映',
        'user', coalesce(v_profile.display_name, ''), 'role', v_profile.role, 'createdAt', v_now,
        'stocktakeSessionId', p_session_id, 'stocktakeLineId', v_line->>'lineId', 'operationId', p_operation_id,
        'beforeQty', v_current, 'applyDifference', v_diff, 'supplier', coalesce(v_line->>'supplier', '')
      ));
      v_special_count := v_special_count + 1;
    end if;
  end loop;

  for v_line in
    select value
      from pg_catalog.jsonb_array_elements(public.v177_require_json_array(v_session->'qrLines', 'QR在庫棚卸し明細'))
     order by value->>'qrKey'
  loop
    perform public.v177_require_json_object(v_line, 'QR在庫棚卸し明細');
    v_qr_key := nullif(pg_catalog.btrim(coalesce(v_line->>'qrKey', v_line->>'qr_key')), '');
    v_snapshot := public.v177_parse_decimal(v_line->>'systemQty', 'QR開始時数量');
    v_actual := public.v177_parse_decimal(v_line->>'actualQty', 'QR実数');
    v_out := coalesce(public.v177_parse_decimal(v_line->>'outQty', 'QR出庫数量'), 0);
    if v_qr_key is null or v_snapshot is null or v_snapshot < 0 or v_actual is null or v_actual < 0 or v_out < 0 then
      raise exception '%：QR棚卸しデータが不正です', coalesce(v_line->>'itemName', 'QRロット') using errcode = '22023';
    end if;

    select * into v_lot
      from public.qr_lots
     where qr_key = v_qr_key
       and coalesce(active, true)
     for update;
    if not found then
      raise exception '%：QRロットが見つからないか無効です', v_qr_key using errcode = 'P0002';
    end if;
    if v_lot.current_qty is distinct from v_snapshot then
      raise exception '%：棚卸し開始後にQR在庫が更新されています。最新在庫で棚卸しをやり直してください', coalesce(v_line->>'itemName', v_qr_key) using errcode = '40001';
    end if;

    v_diff := pg_catalog.round(v_actual - v_snapshot, 3);
    v_destination := pg_catalog.btrim(coalesce(v_line->>'destination', ''));
    if v_diff < 0 then
      if v_destination = '' then
        raise exception '%：QR在庫が減った場合は出庫先を選択してください', coalesce(v_line->>'itemName', v_qr_key) using errcode = '22023';
      end if;
      if nullif(pg_catalog.btrim(coalesce(v_line->>'shipTiming', '')), '') not in ('当日分', '翌日分先送り') then
        raise exception '%：QR在庫が減った場合は出庫区分（当日分／翌日分先送り）を選択してください', coalesce(v_line->>'itemName', v_qr_key) using errcode = '22023';
      end if;
      if v_out <> -v_diff then
        raise exception '%：QR出庫数量は開始時数量－実数と一致させてください', coalesce(v_line->>'itemName', v_qr_key) using errcode = '22023';
      end if;
      v_type := '出庫';
      v_qr_decrease_count := v_qr_decrease_count + 1;
    elsif v_diff > 0 then
      if v_out <> 0 then
        raise exception '%：QR在庫が増えた場合、出庫数量は0にしてください', coalesce(v_line->>'itemName', v_qr_key) using errcode = '22023';
      end if;
      if v_destination <> '' then
        raise exception '%：QR在庫が増えた場合、出庫先は指定できません', coalesce(v_line->>'itemName', v_qr_key) using errcode = '22023';
      end if;
      v_type := '入庫・調整増';
      v_qr_increase_count := v_qr_increase_count + 1;
    else
      if v_out <> 0 or v_destination <> '' then
        raise exception '%：QR差分なしでは出庫数量・出庫先を指定できません', coalesce(v_line->>'itemName', v_qr_key) using errcode = '22023';
      end if;
      v_type := '差分なし';
      v_qr_same_count := v_qr_same_count + 1;
    end if;

    v_hash := pg_catalog.md5(p_operation_id || ':qr:' || v_qr_key);
    v_qr_operation_id := (
      pg_catalog.substr(v_hash, 1, 8) || '-' || pg_catalog.substr(v_hash, 9, 4) || '-' ||
      pg_catalog.substr(v_hash, 13, 4) || '-' || pg_catalog.substr(v_hash, 17, 4) || '-' || pg_catalog.substr(v_hash, 21, 12)
    )::uuid;
    select * into v_existing_movement
      from public.qr_lot_movements
     where operation_id = v_qr_operation_id;
    if found then
      raise exception '%：同じ棚卸し操作IDのQR履歴が既にあります。セッション状態を確認してください', coalesce(v_line->>'itemName', v_qr_key) using errcode = '23505';
    end if;

    v_before_weight := v_lot.current_weight;
    v_after_weight := public.v177_parse_decimal(v_line->>'actualWeightKg', 'QR棚卸し重量kg');
    update public.qr_lots
       set current_qty = v_actual,
           current_weight = coalesce(v_after_weight, current_weight),
           status = case when v_actual > 0 then '在庫あり' else '在庫なし' end,
           updated_at = v_now
     where id = v_lot.id;

    insert into public.qr_lot_movements(
      movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
      qty, unit, destination, storage_location, user_id, user_name, memo,
      container_type, lot_manage_type, weight, before_quantity, after_quantity,
      before_weight, after_weight, weight_status, reason,
      operation_id, device_meta, operation_meta
    ) values (
      v_type, v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id, v_lot.item_name, v_lot.origin, v_lot.supplier, v_lot.cooperative_name,
      pg_catalog.abs(v_diff), v_lot.unit, case when v_type = '出庫' then v_destination else null end, v_lot.storage_location,
      v_profile.id::text, coalesce(v_profile.display_name, ''), coalesce(v_line->>'memo', ''),
      v_lot.container_type, v_lot.lot_manage_type, v_after_weight, v_snapshot, v_actual,
      v_before_weight, coalesce(v_after_weight, v_before_weight), v_lot.weight_status, '棚卸し差異',
      v_qr_operation_id, coalesce(p_device_meta, '{}'::jsonb),
      coalesce(p_operation_meta, '{}'::jsonb) || pg_catalog.jsonb_build_object(
        'source', 'inventory_count_v177', 'session_id', p_session_id, 'count_no', v_session->>'countNo',
        'session_operation_id', p_operation_id, 'snapshot_quantity', v_snapshot, 'actual_quantity', v_actual,
        'ship_timing', nullif(v_line->>'shipTiming', '')
      )
    );
    v_qr_count := v_qr_count + 1;
  end loop;

  v_result := pg_catalog.jsonb_build_object(
    'ok', true, 'idempotent', false, 'sessionId', p_session_id,
    'normalApplied', v_normal_count, 'specialApplied', v_special_count, 'qrApplied', v_qr_count,
    'qrOutbound', v_qr_decrease_count, 'qrIncreaseAdjustment', v_qr_increase_count, 'qrNoDifference', v_qr_same_count,
    'appliedAt', v_now, 'operationId', p_operation_id
  );
  v_new := v_session || pg_catalog.jsonb_build_object(
    'status', 'completed', 'inventoryApplied', true, 'qrApplied', true,
    'v177Applied', true, 'v177AppliedAt', v_now, 'v177AppliedBy', coalesce(v_profile.display_name, ''),
    'v177AppliedById', v_profile.id, 'v177ApplyOperationId', p_operation_id, 'v177ApplyResult', v_result,
    'v177CompletedAt', v_now, 'v177CompletedBy', coalesce(v_profile.display_name, ''),
    'v177CompletedById', v_profile.id, 'revision', v_revision + 1, 'updatedAt', v_now, 'updatedBy', coalesce(v_profile.display_name, ''),
    'v177OperationIds', public.seika_inventory_count_v124_trim_operations(
      public.v177_require_json_array(v_session->'v177OperationIds', '棚卸し操作履歴')
      || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', p_operation_id, 'action', 'apply', 'at', v_now))
    )
  );
  v_data := public.seika_inventory_count_v123_replace_session(v_data, p_session_id, v_new)
    || pg_catalog.jsonb_build_object('records', v_records, 'movements', v_movements, 'specialRecords', v_special_records);
  update public.app_state
     set data = v_data,
         version = version + 1,
         updated_at = v_now
   where id = v_state.id
   returning version into v_version;

  return v_result || pg_catalog.jsonb_build_object('version', v_version);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_create_inventory_count_session(p_id text, p_session jsonb, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_session jsonb;
  v_data jsonb;
  v_existing jsonb;
  v_version bigint;
  v_now timestamptz := pg_catalog.now();
begin
  if p_id <> 'ishioka_inventory_production_v2'
     or pg_catalog.jsonb_typeof(p_session) <> 'object'
     or nullif(pg_catalog.btrim(p_session->>'id'), '') is null
     or p_session->>'room' not in ('room2', 'room3')
     or nullif(pg_catalog.btrim(p_operation_id), '') is null
     or pg_catalog.char_length(p_operation_id) > 200 then
    raise exception '棚卸し開始データが不正です' using errcode = '22023';
  end if;

  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin', 'worker') then
    raise exception '棚卸し開始は管理者・青果社員のみです' using errcode = '42501';
  end if;
  perform public.v177_require_json_array(p_session->'lines', '開始する通常在庫棚卸し明細');
  perform public.v177_require_json_array(p_session->'qrLines', '開始するQR在庫棚卸し明細');

  select * into v_state
    from public.app_state
   where id = p_id
   for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;

  for v_existing in
    select value
      from pg_catalog.jsonb_array_elements(public.v177_inventory_sessions(v_state.data))
  loop
    if v_existing->>'id' = p_session->>'id' then
      if v_existing->>'inventoryCountMode' = 'inventory_apply_v177'
         and v_existing->>'v177CreateOperationId' = p_operation_id then
        return pg_catalog.jsonb_build_object('ok', true, 'idempotent', true, 'version', v_state.version, 'sessionId', v_existing->>'id');
      end if;
      raise exception '同じ棚卸しIDが既に存在します' using errcode = '23505';
    end if;
    if v_existing->>'room' = p_session->>'room'
       and coalesce(v_existing->>'status', '') not in ('completed', 'confirmed', 'test_confirmed', 'reversed', 'cancelled')
       and nullif(v_existing->>'v188ConfirmedAt', '') is null then
      raise exception 'この冷蔵庫には進行中の棚卸しがあります。旧棚卸しを含め新規開始できません' using errcode = '23505';
    end if;
  end loop;

  v_session := p_session || pg_catalog.jsonb_build_object(
      'inventoryCountMode', 'inventory_apply_v177',
      'status', 'counting',
      'normalStatus', coalesce(p_session->>'normalStatus', 'counting'),
      'qrCountStatus', coalesce(p_session->>'qrCountStatus', 'counting'),
      'v177CreateOperationId', p_operation_id,
      'v177OperationIds', '[]'::jsonb,
      'v177Applied', false,
      'v177CreatedAt', v_now,
      'v177CreatedBy', coalesce(v_profile.display_name, ''),
      'v177CreatedById', v_profile.id,
      'revision', coalesce(public.v177_parse_bigint(p_session->>'revision', '開始時リビジョン'), 0) + 1,
      'updatedAt', v_now,
      'updatedBy', coalesce(v_profile.display_name, '')
    );

  v_data := public.seika_inventory_count_v123_replace_session(
    v_state.data,
    v_session->>'id',
    v_session
  );
  update public.app_state
     set data = v_data,
         version = version + 1,
         updated_at = v_now
   where id = v_state.id
   returning version into v_version;

  return pg_catalog.jsonb_build_object('ok', true, 'version', v_version, 'sessionId', v_session->>'id');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_delete_legacy_inventory_count_sessions(p_state_id text, p_expected_version bigint, p_session_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_actor_id uuid := auth.uid();
  v_is_sql_editor boolean := (session_user = 'postgres');
  v_state public.app_state%rowtype;
  v_sessions jsonb;
  v_remaining_sessions jsonb := '[]'::jsonb;
  v_session jsonb;
  v_current_target_ids jsonb := '[]'::jsonb;
  v_requested_ids jsonb := '[]'::jsonb;
  v_deleted_ids jsonb := '[]'::jsonb;
  v_requested_count integer := 0;
  v_deleted_count integer := 0;
  v_current_target_count integer := 0;
  v_invalid_session_count integer := 0;
  v_missing_id_count integer := 0;
  v_duplicate_id_count integer := 0;
  v_remaining_v177_count integer := 0;
  v_version_before bigint;
  v_version_after bigint;
  v_now timestamptz := pg_catalog.now();
  v_requested_id text;
  v_session_id text;
begin
  if p_state_id <> 'ishioka_inventory_production_v2'
     or p_expected_version is null
     or p_expected_version < 0
     or pg_catalog.jsonb_typeof(p_session_ids) <> 'array' then
    raise exception '削除引数が不正です。02のsummary行のstate_id・target_session_idsをそのまま指定してください' using errcode = '22023';
  end if;

  -- SQL Editor は auth.uid() が NULL のため、SECURITY DEFINER の所有者ロール判定ではなく
  -- 呼出し元セッションを示す session_user が postgres の場合だけを明示的に許可する。
  -- API / RPC 経由は従来どおり、有効な admin profile を必須とする。
  if not v_is_sql_editor then
    if v_actor_id is null then
      raise exception 'API経由の旧棚卸し履歴削除にはログインした有効な管理者が必要です' using errcode = '42501';
    end if;
    select p.* into v_profile
      from public.profiles p
     where p.id = v_actor_id;
    if not found
       or v_profile.role <> 'admin'
       or v_profile.active is distinct from true then
      raise exception 'API経由の旧棚卸し履歴削除は有効な管理者だけが実行できます' using errcode = '42501';
    end if;
  end if;

  for v_requested_id in
    select nullif(pg_catalog.btrim(value #>> '{}'), '')
      from pg_catalog.jsonb_array_elements(p_session_ids)
     where pg_catalog.jsonb_typeof(value) = 'string'
  loop
    if v_requested_id is null then
      raise exception '削除対象IDに空値が含まれます' using errcode = '22023';
    end if;
    if pg_catalog.char_length(v_requested_id) > 200 then
      raise exception '削除対象IDが長すぎます' using errcode = '22023';
    end if;
    v_requested_ids := v_requested_ids || pg_catalog.jsonb_build_array(v_requested_id);
    v_requested_count := v_requested_count + 1;
  end loop;
  if v_requested_count <> pg_catalog.jsonb_array_length(p_session_ids) then
    raise exception '削除対象IDに文字列以外が含まれます' using errcode = '22023';
  end if;
  if v_requested_count = 0 then
    raise exception '削除対象IDが0件です。02のsummary行を確認してください' using errcode = '22023';
  end if;
  select pg_catalog.count(*) - pg_catalog.count(distinct value #>> '{}')
    into v_duplicate_id_count
    from pg_catalog.jsonb_array_elements(v_requested_ids);
  if v_duplicate_id_count <> 0 then
    raise exception '削除対象IDに重複があります。02のtarget_session_idsを加工せず使用してください' using errcode = '22023';
  end if;

  select * into v_state
    from public.app_state
   where id = p_state_id
   for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;
  v_version_before := v_state.version;
  -- app_state.versionは通常同期でも変わるため固定比較しない。
  -- FOR UPDATE後、削除対象IDの完全一致で対象変更の有無を検証する。
  if pg_catalog.jsonb_typeof(v_state.data) <> 'object'
     or pg_catalog.jsonb_typeof(v_state.data->'inventoryCounts') <> 'object'
     or pg_catalog.jsonb_typeof(v_state.data->'inventoryCounts'->'sessions') <> 'array' then
    raise exception 'app_state.data.inventoryCounts.sessionsの形式が不正です。データは変更していません' using errcode = '22023';
  end if;
  v_sessions := v_state.data->'inventoryCounts'->'sessions';

  for v_session in
    select value
      from pg_catalog.jsonb_array_elements(v_sessions)
  loop
    if pg_catalog.jsonb_typeof(v_session) <> 'object' then
      v_invalid_session_count := v_invalid_session_count + 1;
      continue;
    end if;
    v_session_id := nullif(pg_catalog.btrim(v_session->>'id'), '');
    if (v_session->>'inventoryCountMode') is distinct from 'inventory_apply_v177' then
      v_current_target_count := v_current_target_count + 1;
      if v_session_id is null then
        v_missing_id_count := v_missing_id_count + 1;
      else
        v_current_target_ids := v_current_target_ids || pg_catalog.jsonb_build_array(v_session_id);
      end if;
    end if;
  end loop;
  if v_invalid_session_count <> 0 or v_missing_id_count <> 0 then
    raise exception 'sessionsに不正な要素またはID未設定の旧セッションがあります。02の結果を確認してください（非object=%、ID未設定=%）', v_invalid_session_count, v_missing_id_count using errcode = '22023';
  end if;
  if v_current_target_count <> v_requested_count
     or v_current_target_ids <> v_requested_ids then
    raise exception '削除対象が確認時と一致しません。02のtarget_session_idsを順序も含めてそのまま指定してください（現在候補=%、指定=%）', v_current_target_ids, v_requested_ids using errcode = '40001';
  end if;

  for v_session in
    select value
      from pg_catalog.jsonb_array_elements(v_sessions)
  loop
    if pg_catalog.jsonb_typeof(v_session) <> 'object' then
      raise exception 'sessionsに不正な要素があります。データは変更していません' using errcode = '22023';
    end if;
    v_session_id := nullif(pg_catalog.btrim(v_session->>'id'), '');
    if (v_session->>'inventoryCountMode') is distinct from 'inventory_apply_v177'
       and v_session_id is not null then
      v_deleted_ids := v_deleted_ids || pg_catalog.jsonb_build_array(v_session_id);
      v_deleted_count := v_deleted_count + 1;
    else
      v_remaining_sessions := v_remaining_sessions || pg_catalog.jsonb_build_array(v_session);
      if v_session->>'inventoryCountMode' = 'inventory_apply_v177' then
        v_remaining_v177_count := v_remaining_v177_count + 1;
      end if;
    end if;
  end loop;
  if v_deleted_count <> v_requested_count
     or v_deleted_ids <> v_requested_ids then
    raise exception '削除対象の再構成に不整合があります。データは変更していません' using errcode = 'XX000';
  end if;

  update public.app_state
     set data = pg_catalog.jsonb_set(
           v_state.data,
           '{inventoryCounts,sessions}',
           v_remaining_sessions,
           false
         ),
         version = version + 1,
         updated_at = v_now
   where id = v_state.id
     and version = v_version_before
   returning version into v_version_after;
  if not found then
    raise exception 'app_stateの更新競合を検出しました。02から再確認してください' using errcode = '40001';
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'stateId', v_state.id,
    'deletedCount', v_deleted_count,
    'deletedSessionIds', v_deleted_ids,
    'versionBefore', v_version_before,
    'versionAfter', v_version_after,
    'deletedAt', v_now,
    'authorizationPath', case when v_is_sql_editor then 'sql_editor_session_user_postgres' else 'api_active_admin_profile' end,
    'deletedById', case when v_is_sql_editor then null else v_profile.id end,
    'deletedBy', case when v_is_sql_editor then 'postgres (Supabase SQL Editor)' else coalesce(v_profile.display_name, '') end,
    'preservedV177SessionCount', v_remaining_v177_count,
    'scope', 'app_state.data.inventoryCounts.sessions only'
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_inventory_sessions(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_data jsonb;
  v_counts jsonb;
begin
  v_data := public.v177_require_json_object(p_data, 'app_state.data');
  v_counts := public.v177_require_json_object(v_data->'inventoryCounts', 'app_state.data.inventoryCounts');
  return public.v177_require_json_array(v_counts->'sessions', 'app_state.data.inventoryCounts.sessions');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_parse_bigint(p_value text, p_label text, p_default bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_text text := nullif(pg_catalog.btrim(coalesce(p_value, '')), '');
begin
  if v_text is null then
    return p_default;
  end if;
  if v_text !~ '^[0-9]+$' then
    raise exception '%は0以上の整数で指定してください', p_label using errcode = '22023';
  end if;
  return v_text::bigint;
exception
  when numeric_value_out_of_range then
    raise exception '%の値が大きすぎます', p_label using errcode = '22003';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_parse_boolean(p_value text, p_label text, p_default boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_text text := pg_catalog.lower(nullif(pg_catalog.btrim(coalesce(p_value, '')), ''));
begin
  if v_text is null then
    return p_default;
  end if;
  if v_text = 'true' then
    return true;
  end if;
  if v_text = 'false' then
    return false;
  end if;
  raise exception '%はtrueまたはfalseで指定してください', p_label using errcode = '22023';
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_parse_decimal(p_value text, p_label text, p_invalid_is_null boolean DEFAULT false)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_text text;
begin
  v_text := nullif(pg_catalog.btrim(pg_catalog.translate(coalesce(p_value, ''), '０１２３４５６７８９．，－＋', '0123456789.,-+')), '');
  if v_text is null then
    return null;
  end if;
  if v_text !~ '^[+-]?(?:(?:[0-9]{1,3}(?:,[0-9]{3})+)|[0-9]+)(?:\.[0-9]*)?$'
     and v_text !~ '^[+-]?\.[0-9]+$' then
    if p_invalid_is_null then
      return null;
    end if;
    raise exception '%は数値で入力してください（カンマは3桁区切りのみ使用できます）', p_label using errcode = '22023';
  end if;
  return pg_catalog.replace(v_text, ',', '')::numeric;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_require_json_array(p_value jsonb, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if pg_catalog.jsonb_typeof(p_value) <> 'array' then
    raise exception '%のデータ形式が不正です。配列である必要があります。既存データは変更していません', p_label using errcode = '22023';
  end if;
  return p_value;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_require_json_object(p_value jsonb, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if pg_catalog.jsonb_typeof(p_value) <> 'object' then
    raise exception '%のデータ形式が不正です。オブジェクトである必要があります。既存データは変更していません', p_label using errcode = '22023';
  end if;
  return p_value;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v177_save_inventory_count_section(p_id text, p_session_id text, p_section text, p_expected_section_revision bigint, p_entries jsonb, p_action text, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_session jsonb;
  v_source jsonb;
  v_entry jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_new jsonb;
  v_data jsonb;
  v_revision bigint;
  v_id text;
  v_revision_key text;
  v_status_key text;
  v_rows_key text;
  v_prefix text;
  v_actual numeric;
  v_weight numeric;
  v_kg numeric;
  v_remainder numeric;
  v_sum numeric;
  v_active boolean;
  v_weight_entries jsonb;
  v_weight_entry jsonb;
  v_missing integer := 0;
  v_count integer;
  v_version bigint;
  v_now timestamptz := pg_catalog.now();
  v_is_kg boolean;
begin
  if p_id <> 'ishioka_inventory_production_v2'
     or p_section not in ('normal', 'qr')
     or p_action not in ('draft', 'submit')
     or pg_catalog.jsonb_typeof(p_entries) <> 'array'
     or nullif(pg_catalog.btrim(p_session_id), '') is null
     or nullif(pg_catalog.btrim(p_operation_id), '') is null
     or pg_catalog.char_length(p_operation_id) > 200 then
    raise exception '棚卸し保存の引数が不正です' using errcode = '22023';
  end if;

  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin', 'worker') then
    raise exception '棚卸しを保存できるのは管理者・青果社員のみです' using errcode = '42501';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;
  select value into v_session
    from pg_catalog.jsonb_array_elements(public.v177_inventory_sessions(v_state.data))
   where value->>'id' = p_session_id
   limit 1;
  if v_session is null then
    raise exception '棚卸しセッションが見つかりません' using errcode = 'P0002';
  end if;

  /* v177 preserves its own two-section session layout. */
  if coalesce(v_session->>'inventoryCountMode', '') <> 'inventory_apply_v177' then
    raise exception '旧棚卸しは変更できません' using errcode = '22023';
  end if;
  if public.v177_parse_boolean(v_session->>'v177Applied', '棚卸し反映済みフラグ', false) then
    raise exception '在庫反映済みの棚卸しは変更できません' using errcode = '22023';
  end if;
  v_revision_key := case p_section when 'normal' then 'normalRevision' else 'qrRevision' end;
  v_status_key := case p_section when 'normal' then 'normalStatus' else 'qrCountStatus' end;
  v_rows_key := case p_section when 'normal' then 'lines' else 'qrLines' end;
  v_prefix := case p_section when 'normal' then 'normal' else 'qr' end;

  if exists (
    select 1
      from pg_catalog.jsonb_array_elements(public.v177_require_json_array(v_session->'v177OperationIds', '棚卸し操作履歴')) x
     where x->>'id' = p_operation_id
  ) then
    return pg_catalog.jsonb_build_object(
      'ok', true, 'idempotent', true, 'version', v_state.version,
      'sectionRevision', coalesce(public.v177_parse_bigint(v_session->>v_revision_key, '工程リビジョン'), 0)
    );
  end if;

  v_revision := coalesce(public.v177_parse_bigint(v_session->>v_revision_key, '工程リビジョン'), 0);
  if p_expected_section_revision is null or p_expected_section_revision <> v_revision then
    return pg_catalog.jsonb_build_object(
      'ok', false, 'conflict', true, 'version', v_state.version,
      'sectionRevision', v_revision, 'message', '別端末で更新されています。'
    );
  end if;
  if v_session->>v_status_key = 'submitted' and p_action = 'draft' then
    raise exception '入力完了済み工程は下書きへ戻せません。修正する場合も入力完了として保存してください' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_typeof(public.seika_inventory_count_v124_section_rows(v_session, p_section)) <> 'array' then
    raise exception '棚卸し対象明細のデータ形式が不正です。既存データは変更していません' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_array_length(p_entries) <> pg_catalog.jsonb_array_length(public.seika_inventory_count_v124_section_rows(v_session, p_section)) then
    raise exception '入力件数が棚卸し対象と一致しません' using errcode = '22023';
  end if;

  for v_source in
    select value from pg_catalog.jsonb_array_elements(public.seika_inventory_count_v124_section_rows(v_session, p_section))
  loop
    perform public.v177_require_json_object(v_source, '棚卸し対象明細');
    v_id := case when p_section = 'qr'
      then nullif(pg_catalog.btrim(coalesce(v_source->>'qrKey', v_source->>'qr_key')), '')
      else nullif(pg_catalog.btrim(v_source->>'lineId'), '') end;
    if v_id is null then
      raise exception '棚卸し明細IDが不正です' using errcode = '22023';
    end if;
    select pg_catalog.count(*) into v_count
      from pg_catalog.jsonb_array_elements(p_entries) x
     where nullif(pg_catalog.btrim(x->>'id'), '') = v_id;
    if v_count <> 1 then
      raise exception '入力明細が不足または重複しています' using errcode = '22023';
    end if;
    select value into v_entry
      from pg_catalog.jsonb_array_elements(p_entries) x
     where nullif(pg_catalog.btrim(x->>'id'), '') = v_id
     limit 1;

    v_is_kg := p_section <> 'qr'
      and (pg_catalog.lower(coalesce(v_source->>'unit', 'kg')) = 'kg' or coalesce(v_source->>'type', '') = 'normal');
    if v_is_kg then
      if pg_catalog.jsonb_typeof(v_entry->'weightEntries') <> 'array'
         or pg_catalog.jsonb_array_length(v_entry->'weightEntries') not between 1 and 20 then
        raise exception '%：量目明細は1〜20行で入力してください', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
      end if;
      v_sum := 0;
      v_active := false;
      v_weight_entries := '[]'::jsonb;
      for v_weight_entry in select value from pg_catalog.jsonb_array_elements(v_entry->'weightEntries') loop
        perform public.v177_require_json_object(v_weight_entry, '量目入力明細');
        v_kg := public.seika_inventory_count_decimal_optional_v123(v_weight_entry->>'packKg', '量目kg');
        v_weight := public.seika_inventory_count_decimal_optional_v123(v_weight_entry->>'caseCount', 'ケース数');
        if nullif(pg_catalog.btrim(coalesce(v_weight_entry->>'packKg', '')), '') is not null
           or nullif(pg_catalog.btrim(coalesce(v_weight_entry->>'caseCount', '')), '') is not null then
          if v_kg is null or v_kg <= 0 or v_weight is null or v_weight < 0 then
            raise exception '%：量目kgは0より大きく、ケース数は0以上で入力してください', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
          end if;
          v_sum := v_sum + v_kg * v_weight;
          v_active := true;
        end if;
        v_weight_entries := v_weight_entries || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'id', pg_catalog.left(coalesce(v_weight_entry->>'id', ''), 100),
          'packKg', coalesce(v_kg::text, ''),
          'caseCount', coalesce(v_weight::text, '')
        ));
      end loop;
      v_remainder := public.seika_inventory_count_decimal_optional_v123(v_entry->>'remainderKg', '端数kg');
      if v_remainder is not null and v_remainder < 0 then
        raise exception '%：端数kgは0以上です', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
      end if;
      if v_remainder is not null then
        v_sum := v_sum + v_remainder;
        v_active := true;
      end if;
      v_actual := case when v_active then pg_catalog.round(v_sum, 3) else null end;
      if p_action = 'submit'
         and public.v177_parse_boolean(v_entry->>'supplierRequired', '仕入先必須フラグ', false)
         and pg_catalog.btrim(coalesce(v_entry->>'supplier', '')) = '' then
        raise exception '%：仕入先を入力してください', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
      end if;
      v_source := v_source || pg_catalog.jsonb_build_object(
        'weightEntries', v_weight_entries, 'remainderKg', coalesce(v_remainder::text, ''),
        'inputMode', 'weight_entries', 'actualQty', v_actual,
        'supplier', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'supplier', '')), 160),
        'supplierRequired', public.v177_parse_boolean(v_entry->>'supplierRequired', '仕入先必須フラグ', false),
        'memo', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'memo', '')), 1000)
      );
    elsif p_section = 'qr' then
      v_actual := public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty', '実数');
      if v_actual is not null and v_actual < 0 then
        raise exception '%：実数は0以上です', coalesce(v_source->>'itemName', 'QRロット') using errcode = '22023';
      end if;
      v_weight := public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualWeightKg', '棚卸し重量kg');
      if v_weight is not null and v_weight < 0 then
        raise exception '%：棚卸し重量kgは0以上です', coalesce(v_source->>'itemName', 'QRロット') using errcode = '22023';
      end if;
      if p_action = 'submit'
         and coalesce(v_source->>'unit', '') = '基'
         and v_actual is not null and v_weight is null
         and (coalesce(public.v177_parse_decimal(v_source->>'snapshotTotalWeight', 'QR開始時総重量'), 0) <= 0
           or coalesce(public.v177_parse_decimal(v_source->>'snapshotInitialQty', 'QR開始時数量'), 0) <= 0) then
        raise exception '%：大型容器は棚卸し重量kgを入力してください', coalesce(v_source->>'itemName', 'QRロット') using errcode = '22023';
      end if;
      v_source := v_source || pg_catalog.jsonb_build_object(
        'actualQty', v_actual,
        'actualWeightKg', v_weight,
        'outQty', coalesce(public.seika_inventory_count_decimal_optional_v123(v_entry->>'outQty', '出庫数量'), 0),
        'destination', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'destination', '')), 160),
        'shipTiming', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'shipTiming', '')), 80),
        'memo', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'memo', '')), 1000)
      );
    else
      v_actual := public.seika_inventory_count_decimal_optional_v123(v_entry->>'actualQty', '実数');
      v_kg := public.seika_inventory_count_decimal_optional_v123(v_entry->>'kgPerUnit', '1単位あたりkg');
      if v_actual is not null and v_actual < 0 then
        raise exception '%：実数は0以上です', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
      end if;
      if v_kg is not null and v_kg <= 0 then
        raise exception '%：1単位あたりkgは0より大きい値です', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
      end if;
      if p_action = 'submit'
         and public.v177_parse_boolean(v_entry->>'supplierRequired', '仕入先必須フラグ', false)
         and pg_catalog.btrim(coalesce(v_entry->>'supplier', '')) = '' then
        raise exception '%：仕入先を入力してください', coalesce(v_source->>'itemName', '品目') using errcode = '22023';
      end if;
      v_source := v_source || pg_catalog.jsonb_build_object(
        'actualQty', v_actual, 'kgPerUnit', coalesce(v_kg::text, ''),
        'supplier', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'supplier', '')), 160),
        'supplierRequired', public.v177_parse_boolean(v_entry->>'supplierRequired', '仕入先必須フラグ', false),
        'memo', pg_catalog.left(pg_catalog.btrim(coalesce(v_entry->>'memo', '')), 1000)
      );
    end if;

    if (v_source->>'actualQty') is null or v_source->>'actualQty' = '' then
      v_missing := v_missing + 1;
    end if;
    v_rows := v_rows || pg_catalog.jsonb_build_array(v_source || pg_catalog.jsonb_build_object(
      'status', case when (v_source->>'actualQty') is null then 'unentered' else 'entered' end
    ));
  end loop;

  if p_action = 'submit' and v_missing > 0 then
    raise exception '未入力が%件あります。未入力のまま保存する場合は下書き保存を選んでください', v_missing using errcode = '22023';
  end if;

  v_new := v_session || pg_catalog.jsonb_build_object(
    v_rows_key, v_rows,
    v_status_key, case when p_action = 'submit' then 'submitted' when v_missing > 0 then 'incomplete' else 'counting' end,
    v_revision_key, v_revision + 1,
    pg_catalog.format('%sSavedAt', v_prefix), v_now,
    pg_catalog.format('%sSavedBy', v_prefix), coalesce(v_profile.display_name, ''),
    pg_catalog.format('%sSavedById', v_prefix), v_profile.id,
    pg_catalog.format('%sSubmittedAt', v_prefix), case when p_action = 'submit' then v_now else null end,
    pg_catalog.format('%sSubmittedBy', v_prefix), case when p_action = 'submit' then coalesce(v_profile.display_name, '') else null end,
    pg_catalog.format('%sSubmittedById', v_prefix), case when p_action = 'submit' then v_profile.id else null end
  );
  v_new := v_new || pg_catalog.jsonb_build_object(
    'status', public.seika_inventory_count_v124_status(v_new),
    'revision', coalesce(public.v177_parse_bigint(v_session->>'revision', '棚卸しリビジョン'), 0) + 1,
    'updatedAt', v_now,
    'updatedBy', coalesce(v_profile.display_name, ''),
    'v177OperationIds', public.seika_inventory_count_v124_trim_operations(
      public.v177_require_json_array(v_session->'v177OperationIds', '棚卸し操作履歴')
      || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', p_operation_id, 'section', p_section, 'action', p_action, 'at', v_now))
    )
  );
  v_data := public.seika_inventory_count_v123_replace_session(v_state.data, p_session_id, v_new);
  update public.app_state
     set data = v_data,
         version = version + 1,
         updated_at = v_now
   where id = v_state.id
   returning version into v_version;

  return pg_catalog.jsonb_build_object(
    'ok', true, 'version', v_version, 'sectionRevision', v_revision + 1,
    'missing', v_missing, 'status', v_new->>'status'
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v186_confirm_live_inventory_count(p_id text, p_session_id text, p_expected_session_revision bigint, p_expected_state_version bigint, p_lines jsonb, p_qr_lines jsonb, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_session jsonb;
  v_new jsonb;
  v_data jsonb;
  v_version bigint;
  v_revision bigint;
  v_now timestamptz := pg_catalog.now();
begin
  if p_id <> 'ishioka_inventory_production_v2'
     or nullif(pg_catalog.btrim(p_session_id), '') is null
     or nullif(pg_catalog.btrim(p_operation_id), '') is null
     or pg_catalog.char_length(p_operation_id) > 200
     or pg_catalog.jsonb_typeof(p_lines) <> 'array'
     or pg_catalog.jsonb_typeof(p_qr_lines) <> 'array' then
    raise exception '棚卸し確定データが不正です' using errcode = '22023';
  end if;

  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin', 'worker') then
    raise exception '棚卸しを確定できるのは管理者・青果社員のみです' using errcode = '42501';
  end if;

  select * into v_state
    from public.app_state
   where id = p_id
   for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;

  select value into v_session
    from pg_catalog.jsonb_array_elements(public.v177_inventory_sessions(v_state.data))
   where value->>'id' = p_session_id
   limit 1;
  if v_session is null then
    raise exception '棚卸しセッションが見つかりません' using errcode = 'P0002';
  end if;
  if coalesce(v_session->>'inventoryCountMode', '') <> 'inventory_apply_v177'
     or coalesce(v_session->>'liveSnapshotMode', '') <> 'live_snapshot_v186' then
    raise exception '旧棚卸しはこの確定処理で変更できません' using errcode = '22023';
  end if;

  if p_expected_state_version is null or p_expected_state_version <> v_state.version then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'conflict', true,
      'version', v_state.version,
      'message', '在庫データが別端末で更新されています。最新データを再読込してください。'
    );
  end if;

  if coalesce((v_session->>'v186LiveSnapshotConfirmed')::boolean, false) then
    if v_session->>'v186ConfirmOperationId' = p_operation_id then
      return pg_catalog.jsonb_build_object(
        'ok', true,
        'idempotent', true,
        'version', v_state.version,
        'session', v_session
      );
    end if;
    raise exception 'この棚卸しは確定済みです' using errcode = '22023';
  end if;

  v_revision := coalesce(public.v177_parse_bigint(v_session->>'revision', '棚卸しリビジョン'), 0);
  if p_expected_session_revision is null or p_expected_session_revision <> v_revision then
    return pg_catalog.jsonb_build_object(
      'ok', false,
      'conflict', true,
      'version', v_state.version,
      'revision', v_revision,
      'message', '別端末で棚卸しが更新されています。再読込してください。'
    );
  end if;

  v_new := v_session || pg_catalog.jsonb_build_object(
    'lines', p_lines,
    'qrLines', p_qr_lines,
    'status', 'completed',
    'normalStatus', 'submitted',
    'qrCountStatus', 'submitted',
    'v186LiveSnapshotConfirmed', true,
    'v186ConfirmedAt', v_now,
    'v186ConfirmedBy', coalesce(v_profile.display_name, ''),
    'v186ConfirmedById', v_profile.id,
    'v186ConfirmOperationId', p_operation_id,
    'v186SnapshotRule', '確定ボタン押下時点の最新在庫',
    'v177Applied', false,
    'v186InventoryOperationApplied', false,
    'inventoryApplied', false,
    'qrApplied', false,
    'revision', v_revision + 1,
    'updatedAt', v_now,
    'updatedBy', coalesce(v_profile.display_name, '')
  );

  v_data := public.seika_inventory_count_v123_replace_session(
    v_state.data,
    p_session_id,
    v_new
  );

  update public.app_state
     set data = v_data,
         version = version + 1,
         updated_at = v_now
   where id = v_state.id
   returning version into v_version;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'version', v_version,
    'revision', v_revision + 1,
    'session', v_new
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.v188_apply_month_end_qr_adjustment(p_qr_key text, p_operation_id text, p_target_month text, p_as_of_date text, p_book_qty numeric, p_actual_qty numeric, p_reason text, p_memo text, p_session_id text, p_count_no text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_diff numeric;
  v_current_qty numeric;
  v_after_qty numeric;
  v_stored_after_qty numeric;
  v_movement_type text;
  v_occurred_at timestamptz;
  v_memo text;
  v_payload jsonb;
  v_cols text;
  v_has_current_weight boolean;
  v_is_large_container boolean;
  v_per_unit_weight numeric;
  v_current_weight numeric;
  v_after_weight numeric;
begin
  if nullif(pg_catalog.btrim(p_qr_key), '') is null
     or nullif(pg_catalog.btrim(p_operation_id), '') is null
     or nullif(pg_catalog.btrim(p_target_month), '') is null
     or nullif(pg_catalog.btrim(p_as_of_date), '') is null
     or p_book_qty is null
     or p_actual_qty is null
     or nullif(pg_catalog.btrim(p_session_id), '') is null
     or nullif(pg_catalog.btrim(p_count_no), '') is null
     or p_target_month !~ '^[0-9]{4}-[0-9]{2}$'
     or p_as_of_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or pg_catalog.left(p_as_of_date, 7) <> p_target_month then
    raise exception '月末棚卸しQR調整データが不正です' using errcode = '22023';
  end if;

  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin', 'worker') then
    raise exception '棚卸しを操作できるのは管理者・青果社員のみです' using errcode = '42501';
  end if;

  if exists (
    select 1
      from public.qr_lot_movements
     where operation_id::text = p_operation_id
  ) then
    return pg_catalog.jsonb_build_object('ok', true, 'idempotent', true);
  end if;

  select * into v_lot
    from public.qr_lots
   where qr_key = p_qr_key
   for update;
  if not found then
    raise exception 'QRロットが見つかりません' using errcode = 'P0002';
  end if;

  v_diff := p_actual_qty - p_book_qty;
  if v_diff = 0 then
    return pg_catalog.jsonb_build_object('ok', true, 'skipped', true);
  end if;

  v_current_qty := coalesce((pg_catalog.to_jsonb(v_lot)->>'current_qty')::numeric, 0);
  v_after_qty := v_current_qty + v_diff;
  v_stored_after_qty := greatest(0::numeric, v_after_qty);
  v_movement_type := case when v_diff > 0 then '棚卸し調整増' else '棚卸し調整減' end;
  v_occurred_at := (p_as_of_date || ' 23:59:59')::timestamp at time zone 'Asia/Tokyo';
  v_memo := '対象月' || p_target_month || ' 月末棚卸し（基準日' || p_as_of_date || '）/ 棚卸し番号 ' || p_count_no
    || ' / 帳簿' || p_book_qty::text || '→実数' || p_actual_qty::text
    || case when nullif(pg_catalog.btrim(p_memo), '') is null then '' else ' / ' || p_memo end;

  v_has_current_weight := exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'qr_lots'
       and column_name = 'current_weight'
  );
  v_is_large_container := coalesce(pg_catalog.to_jsonb(v_lot)->>'container_type', '')
    in ('網コンテナ', '鉄コンテナ', 'パレテーナ');
  v_per_unit_weight := case
    when v_is_large_container
     and nullif(pg_catalog.to_jsonb(v_lot)->>'total_weight', '') is not null
     and coalesce(
           nullif(pg_catalog.to_jsonb(v_lot)->>'received_qty', ''),
           nullif(pg_catalog.to_jsonb(v_lot)->>'initial_quantity', '')
         ) is not null
     and coalesce(
           nullif(pg_catalog.to_jsonb(v_lot)->>'received_qty', ''),
           nullif(pg_catalog.to_jsonb(v_lot)->>'initial_quantity', '')
         )::numeric > 0
    then (pg_catalog.to_jsonb(v_lot)->>'total_weight')::numeric
       / coalesce(
           nullif(pg_catalog.to_jsonb(v_lot)->>'received_qty', ''),
           nullif(pg_catalog.to_jsonb(v_lot)->>'initial_quantity', '')
         )::numeric
    else null
  end;
  v_current_weight := case
    when v_has_current_weight then (pg_catalog.to_jsonb(v_lot)->>'current_weight')::numeric
    else null
  end;
  v_after_weight := case
    when v_has_current_weight and v_per_unit_weight is not null
    then greatest(0::numeric, coalesce(v_current_weight, 0) + v_diff * v_per_unit_weight)
    else null
  end;

  v_payload := pg_catalog.jsonb_build_object(
    'qr_key', p_qr_key,
    'lot_id', pg_catalog.to_jsonb(v_lot)->'id',
    'lot_no', pg_catalog.to_jsonb(v_lot)->>'lot_no',
    'item_name', pg_catalog.to_jsonb(v_lot)->>'item_name',
    'unit', pg_catalog.to_jsonb(v_lot)->>'unit',
    'movement_type', v_movement_type,
    'qty', pg_catalog.abs(v_diff),
    'quantity', pg_catalog.abs(v_diff),
    'before_quantity', v_current_qty,
    'after_quantity', v_stored_after_qty,
    'weight', case when v_per_unit_weight is null then null else pg_catalog.abs(v_diff) * v_per_unit_weight end,
    'before_weight', v_current_weight,
    'after_weight', v_after_weight,
    'storage_location', pg_catalog.to_jsonb(v_lot)->>'storage_location',
    'origin', pg_catalog.to_jsonb(v_lot)->>'origin',
    'supplier', pg_catalog.to_jsonb(v_lot)->>'supplier',
    'cooperative_name', pg_catalog.to_jsonb(v_lot)->>'cooperative_name',
    'user_id', v_profile.id,
    'user_name', coalesce(v_profile.display_name, ''),
    'reason', p_reason,
    'memo', v_memo,
    'operation_id', p_operation_id,
    'created_at', v_occurred_at,
    'occurred_at', v_occurred_at
  );

  select pg_catalog.string_agg(pg_catalog.quote_ident(column_name), ', ' order by ordinal_position)
    into v_cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'qr_lot_movements'
     and column_name = any (array[
       'qr_key', 'lot_id', 'lot_no', 'item_name', 'unit', 'movement_type', 'qty', 'quantity',
       'before_quantity', 'after_quantity', 'weight', 'before_weight', 'after_weight',
       'storage_location', 'origin', 'supplier', 'cooperative_name',
       'user_id', 'user_name', 'reason', 'memo', 'operation_id', 'created_at', 'occurred_at'
     ]);
  if v_cols is null then
    raise exception 'QR在庫履歴の挿入可能列が見つかりません' using errcode = 'P0002';
  end if;

  execute pg_catalog.format(
    'insert into public.qr_lot_movements (%s) select %s from pg_catalog.jsonb_populate_record(null::public.qr_lot_movements, $1)',
    v_cols,
    v_cols
  ) using v_payload;

  if v_has_current_weight and v_per_unit_weight is not null then
    execute 'update public.qr_lots set current_qty = $1, current_weight = $2, updated_at = pg_catalog.now() where qr_key = $3'
      using v_stored_after_qty, v_after_weight, p_qr_key;
  else
    update public.qr_lots
       set current_qty = v_stored_after_qty,
           updated_at = pg_catalog.now()
     where qr_key = p_qr_key;
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'diff', v_diff,
    'after_qty', v_stored_after_qty,
    'movement_type', v_movement_type
  );
end;
$function$
;

-- ===== ビュー

-- ===== 外部キー
alter table public.app_admins add constraint app_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.app_state_backup_slots_v1167 add constraint app_state_backup_slots_v1167_content_hash_fkey FOREIGN KEY (content_hash) REFERENCES app_state_backup_blobs_v1167(content_hash) ON DELETE RESTRICT;
alter table public.inventory add constraint inventory_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.qr_lot_delete_audit_events_v1119 add constraint qr_lot_delete_audit_events_v1119_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.qr_lot_movements add constraint qr_lot_movements_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES qr_lots(id) ON DELETE SET NULL;
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_evaluated_by_fkey FOREIGN KEY (evaluated_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_invalidated_by_fkey FOREIGN KEY (invalidated_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.qr_quality_evaluations add constraint qr_quality_evaluations_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES qr_quality_evaluations(id) ON DELETE RESTRICT;
alter table public.qr_quality_photos add constraint qr_quality_photos_evaluation_id_fkey FOREIGN KEY (evaluation_id) REFERENCES qr_quality_evaluations(id) ON DELETE RESTRICT;
alter table public.qr_quality_photos add constraint qr_quality_photos_invalidated_by_fkey FOREIGN KEY (invalidated_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.qr_quality_photos add constraint qr_quality_photos_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.qr_scan_logs add constraint qr_scan_logs_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES qr_lots(id) ON DELETE SET NULL;
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_evaluation_id_fkey FOREIGN KEY (evaluation_id) REFERENCES qr_quality_evaluations(id) ON DELETE CASCADE;
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_recipient_profile_id_fkey FOREIGN KEY (recipient_profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.quality_push_queue_v1144 add constraint quality_push_queue_v1144_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES web_push_subscriptions_v1144(id) ON DELETE CASCADE;
alter table public.seika_feature_modes_v1136 add constraint seika_feature_modes_v1136_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_feedback_reports add constraint seika_feedback_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_feedback_reports add constraint seika_feedback_reports_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_recommended_lot_id_fkey FOREIGN KEY (recommended_lot_id) REFERENCES qr_lots(id) ON DELETE RESTRICT;
alter table public.seika_fifo_decision_audit_v1136 add constraint seika_fifo_decision_audit_v1136_selected_lot_id_fkey FOREIGN KEY (selected_lot_id) REFERENCES qr_lots(id) ON DELETE RESTRICT;
alter table public.seika_fifo_hold_override_audit_v1136 add constraint seika_fifo_hold_override_audit_v1136_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_hold_override_audit_v1136 add constraint seika_fifo_hold_override_audit_v1136_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES qr_lots(id) ON DELETE RESTRICT;
alter table public.seika_fifo_lot_holds_v1136 add constraint seika_fifo_lot_holds_v1136_held_by_fkey FOREIGN KEY (held_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_lot_holds_v1136 add constraint seika_fifo_lot_holds_v1136_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES qr_lots(id) ON DELETE RESTRICT;
alter table public.seika_fifo_lot_holds_v1136 add constraint seika_fifo_lot_holds_v1136_released_by_fkey FOREIGN KEY (released_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_mode_transition_approvals_v1136 add constraint seika_fifo_mode_transition_approvals_v1136_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_fifo_operation_requests_v1136 add constraint seika_fifo_operation_requests_v1136_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES qr_lots(id) ON DELETE RESTRICT;
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_item_aging_policies_v1136 add constraint seika_item_aging_policies_v1136_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.seika_monthly_archives add constraint seika_monthly_archives_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.seika_monthly_archives add constraint seika_monthly_archives_excel_created_by_fkey FOREIGN KEY (excel_created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.seika_monthly_archives add constraint seika_monthly_archives_excel_saved_by_fkey FOREIGN KEY (excel_saved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.seika_policy_audit_v1136 add constraint seika_policy_audit_v1136_audited_by_fkey FOREIGN KEY (audited_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public.stock_movements add constraint stock_movements_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE;
alter table public.trimming_job_lots add constraint trimming_job_lots_trimming_job_id_fkey FOREIGN KEY (trimming_job_id) REFERENCES trimming_jobs(id) ON DELETE CASCADE;
alter table public.trimming_job_outputs add constraint trimming_job_outputs_trimming_job_id_fkey FOREIGN KEY (trimming_job_id) REFERENCES trimming_jobs(id) ON DELETE CASCADE;
alter table public.web_push_subscriptions_v1144 add constraint web_push_subscriptions_v1144_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- ===== トリガー
CREATE TRIGGER trg_backup_app_state_before_update_v185 BEFORE UPDATE OF data ON public.app_state FOR EACH ROW EXECUTE FUNCTION backup_app_state_before_update_v185();
alter table public.app_state disable trigger trg_backup_app_state_before_update_v185;
CREATE TRIGGER trg_capture_app_state_backup_v1167 BEFORE UPDATE OF data ON public.app_state FOR EACH ROW EXECUTE FUNCTION capture_app_state_backup_v1167();
CREATE TRIGGER trg_guard_app_state_update_v185 BEFORE UPDATE OF data ON public.app_state FOR EACH ROW EXECUTE FUNCTION guard_app_state_update_v185();
CREATE TRIGGER trg_qr_destinations_updated_at BEFORE UPDATE ON public.qr_destinations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER guard_seika_qr_write_v187 BEFORE INSERT OR DELETE OR UPDATE ON public.qr_inventory_sessions FOR EACH ROW EXECUTE FUNCTION guard_seika_qr_write_v187();
CREATE TRIGGER guard_seika_qr_write_v187 BEFORE INSERT OR DELETE OR UPDATE ON public.qr_lot_movements FOR EACH ROW EXECUTE FUNCTION guard_seika_qr_write_v187();
CREATE TRIGGER guard_seika_qr_write_v187 BEFORE INSERT OR DELETE OR UPDATE ON public.qr_lots FOR EACH ROW EXECUTE FUNCTION guard_seika_qr_write_v187();
CREATE TRIGGER seika_qr_block_lot_hard_delete_v1119 BEFORE DELETE ON public.qr_lots FOR EACH ROW EXECUTE FUNCTION seika_qr_block_lot_hard_delete_v1119();
CREATE TRIGGER seika_qr_guard_lot_soft_delete_v1119 BEFORE UPDATE OF active ON public.qr_lots FOR EACH ROW EXECUTE FUNCTION seika_qr_guard_lot_soft_delete_v1119();
CREATE TRIGGER seika_v1144_fill_purchase_staff_identity_trg BEFORE INSERT OR UPDATE OF purchase_staff, purchase_staff_profile_id, purchase_staff_legacy_user_id ON public.qr_lots FOR EACH ROW EXECUTE FUNCTION seika_v1144_fill_purchase_staff_identity();
CREATE TRIGGER trg_qr_lots_updated_at BEFORE UPDATE ON public.qr_lots FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_qr_monthly_exports_updated_at BEFORE UPDATE ON public.qr_monthly_exports FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER seika_enqueue_low_quality_push_v1144_trg AFTER INSERT ON public.qr_quality_evaluations FOR EACH ROW EXECUTE FUNCTION seika_enqueue_low_quality_push_v1144();
CREATE TRIGGER seika_qr_guard_quality_invalidation_v1119 BEFORE UPDATE OF active ON public.qr_quality_evaluations FOR EACH ROW EXECUTE FUNCTION seika_qr_guard_quality_invalidation_v1119();
CREATE TRIGGER seika_quality_archive_before_insert_v1102 BEFORE INSERT ON public.qr_quality_evaluations FOR EACH ROW EXECUTE FUNCTION seika_quality_archive_before_insert_v1102();
CREATE TRIGGER seika_qr_guard_quality_photo_invalidation_v1119 BEFORE UPDATE OF active ON public.qr_quality_photos FOR EACH ROW EXECUTE FUNCTION seika_qr_guard_quality_photo_invalidation_v1119();
CREATE TRIGGER seika_quality_archive_after_photo_finalize_v1102 AFTER UPDATE OF upload_status ON public.qr_quality_photos FOR EACH ROW EXECUTE FUNCTION seika_quality_archive_after_photo_finalize_v1102();
CREATE TRIGGER guard_seika_qr_write_v187 BEFORE INSERT OR DELETE OR UPDATE ON public.qr_scan_logs FOR EACH ROW EXECUTE FUNCTION guard_seika_qr_write_v187();
CREATE TRIGGER trg_qr_storage_locations_updated_at BEFORE UPDATE ON public.qr_storage_locations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER seika_admin_notice_audit_block_mutation_v1150 BEFORE DELETE OR UPDATE OR TRUNCATE ON public.seika_admin_notice_audit_v1150 FOR EACH STATEMENT EXECUTE FUNCTION seika_admin_notice_audit_guard_v1150();
CREATE TRIGGER seika_guard_old_waste_delete_v1101 BEFORE DELETE ON public.waste_records FOR EACH ROW EXECUTE FUNCTION seika_guard_old_waste_delete_v1101();

-- ===== RLS
alter table public.app_admins enable row level security;
alter table public.app_settings enable row level security;
alter table public.app_state enable row level security;
alter table public.app_state_backup_20260710 enable row level security;
alter table public.app_state_backup_20260721 enable row level security;
alter table public.app_state_backup_blobs_v1167 enable row level security;
alter table public.app_state_backup_migration_audit_v1167 enable row level security;
alter table public.app_state_backup_slots_v1167 enable row level security;
alter table public.app_state_backups enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.inventory_records enable row level security;
alter table public.items enable row level security;
alter table public.notifications enable row level security;
alter table public.profiles enable row level security;
alter table public.purchase_prices enable row level security;
alter table public.qr_destinations enable row level security;
alter table public.qr_inventory_sessions enable row level security;
alter table public.qr_lot_delete_audit_events_v1119 enable row level security;
alter table public.qr_lot_monthly_snapshots enable row level security;
alter table public.qr_lot_movements enable row level security;
alter table public.qr_lot_movements_backup_20260721 enable row level security;
alter table public.qr_lots enable row level security;
alter table public.qr_lots_backup_20260721 enable row level security;
alter table public.qr_monthly_exports enable row level security;
alter table public.qr_quality_evaluations enable row level security;
alter table public.qr_quality_photos enable row level security;
alter table public.qr_scan_logs enable row level security;
alter table public.qr_settings enable row level security;
alter table public.qr_storage_locations enable row level security;
alter table public.quality_push_queue_v1144 enable row level security;
alter table public.seika_admin_notice_audit_v1150 enable row level security;
alter table public.seika_admin_notice_operations_v1150 enable row level security;
alter table public.seika_admin_notices_v1150 enable row level security;
alter table public.seika_auth_migration_log_v1200 enable row level security;
alter table public.seika_feature_modes_v1136 enable row level security;
alter table public.seika_feedback_reports enable row level security;
alter table public.seika_fifo_decision_audit_v1136 enable row level security;
alter table public.seika_fifo_hold_override_audit_v1136 enable row level security;
alter table public.seika_fifo_lot_holds_v1136 enable row level security;
alter table public.seika_fifo_mode_transition_approvals_v1136 enable row level security;
alter table public.seika_fifo_operation_requests_v1136 enable row level security;
alter table public.seika_inventory_counts_backup_v1205 enable row level security;
alter table public.seika_item_aging_policies_v1136 enable row level security;
alter table public.seika_monthly_archives enable row level security;
alter table public.seika_policy_audit_v1136 enable row level security;
alter table public.seika_policy_backup_v1203 enable row level security;
alter table public.seika_qr_operation_requests_v1156 enable row level security;
alter table public.seika_rpc_test_result enable row level security;
alter table public.stock_movements enable row level security;
alter table public.trimming_job_cancel_audit_v1144 enable row level security;
alter table public.trimming_job_lots enable row level security;
alter table public.trimming_job_outputs enable row level security;
alter table public.trimming_jobs enable row level security;
alter table public.user_admin_audit_logs enable row level security;
alter table public.waste_records enable row level security;
alter table public.web_push_subscriptions_v1144 enable row level security;

-- ===== ポリシー
create policy inventory_movements_modify on public.inventory_movements as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy inventory_movements_read on public.inventory_movements as PERMISSIVE for SELECT to authenticated using (true);
create policy inventory_movements_remove on public.inventory_movements as PERMISSIVE for DELETE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy inventory_movements_write on public.inventory_movements as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy inventory_records_modify on public.inventory_records as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy inventory_records_read on public.inventory_records as PERMISSIVE for SELECT to authenticated using (true);
create policy inventory_records_remove on public.inventory_records as PERMISSIVE for DELETE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy inventory_records_write on public.inventory_records as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy profiles_select_self_or_admin on public.profiles as PERMISSIVE for SELECT to authenticated using (((id = auth.uid()) OR has_any_role(ARRAY['admin'::text])));
create policy purchase_prices_authenticated_read on public.purchase_prices as PERMISSIVE for SELECT to authenticated using ((auth.uid() IS NOT NULL));
create policy qr_destinations_admin_delete on public.qr_destinations as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_destinations_auth_select on public.qr_destinations as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_destinations_staff_insert on public.qr_destinations as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_destinations_staff_update on public.qr_destinations as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_sessions_admin_delete on public.qr_inventory_sessions as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_sessions_auth_select on public.qr_inventory_sessions as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_sessions_staff_insert on public.qr_inventory_sessions as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_sessions_staff_update on public.qr_inventory_sessions as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_snapshot_authenticated_read on public.qr_lot_monthly_snapshots as PERMISSIVE for SELECT to authenticated using (true);
create policy qr_moves_admin_delete on public.qr_lot_movements as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_moves_auth_select on public.qr_lot_movements as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_moves_staff_insert on public.qr_lot_movements as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_moves_staff_update on public.qr_lot_movements as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_lots_admin_delete on public.qr_lots as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_lots_auth_select on public.qr_lots as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_lots_staff_insert on public.qr_lots as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_lots_staff_update on public.qr_lots as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_exports_admin_delete on public.qr_monthly_exports as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_exports_admin_insert on public.qr_monthly_exports as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = 'admin'::text));
create policy qr_exports_admin_select on public.qr_monthly_exports as PERMISSIVE for SELECT to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_exports_admin_update on public.qr_monthly_exports as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = 'admin'::text)) with check ((current_app_role() = 'admin'::text));
create policy qr_scans_admin_delete on public.qr_scan_logs as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_scans_admin_update on public.qr_scan_logs as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = 'admin'::text)) with check ((current_app_role() = 'admin'::text));
create policy qr_scans_auth_select on public.qr_scan_logs as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_scans_staff_insert on public.qr_scan_logs as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_settings_admin_delete on public.qr_settings as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_settings_auth_select on public.qr_settings as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_settings_staff_insert on public.qr_settings as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_settings_staff_update on public.qr_settings as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_storage_locations_admin_delete on public.qr_storage_locations as PERMISSIVE for DELETE to authenticated using ((current_app_role() = 'admin'::text));
create policy qr_storage_locations_auth_select on public.qr_storage_locations as PERMISSIVE for SELECT to authenticated using (is_active_user());
create policy qr_storage_locations_staff_insert on public.qr_storage_locations as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy qr_storage_locations_staff_update on public.qr_storage_locations as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text])));
create policy trimming_job_lots_authenticated_read on public.trimming_job_lots as PERMISSIVE for SELECT to authenticated using ((auth.uid() IS NOT NULL));
create policy trimming_job_outputs_authenticated_read on public.trimming_job_outputs as PERMISSIVE for SELECT to authenticated using ((auth.uid() IS NOT NULL));
create policy trimming_jobs_authenticated_read on public.trimming_jobs as PERMISSIVE for SELECT to authenticated using ((auth.uid() IS NOT NULL));
create policy waste_records_modify on public.waste_records as PERMISSIVE for UPDATE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text, 'sales'::text, 'clerk'::text]))) with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text, 'sales'::text, 'clerk'::text])));
create policy waste_records_read on public.waste_records as PERMISSIVE for SELECT to authenticated using (true);
create policy waste_records_remove on public.waste_records as PERMISSIVE for DELETE to authenticated using ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text, 'clerk'::text])));
create policy waste_records_write on public.waste_records as PERMISSIVE for INSERT to authenticated with check ((current_app_role() = ANY (ARRAY['admin'::text, 'worker'::text, 'sales'::text, 'clerk'::text])));

-- ===== 関数の実行権限
revoke all on function public.acknowledge_qr_quality_evaluation_v1103(uuid) from public;
grant execute on function public.acknowledge_qr_quality_evaluation_v1103(uuid) to service_role;
grant execute on function public.acknowledge_qr_quality_evaluation_v1103(uuid) to authenticated;
revoke all on function public.admin_feedback_count_v195() from public;
grant execute on function public.admin_feedback_count_v195() to authenticated;
grant execute on function public.admin_feedback_count_v195() to service_role;
revoke all on function public.admin_list_feedback_reports_v195() from public;
grant execute on function public.admin_list_feedback_reports_v195() to authenticated;
grant execute on function public.admin_list_feedback_reports_v195() to service_role;
revoke all on function public.admin_update_feedback_report_v195(uuid, text, text, timestamp with time zone, uuid) from public;
grant execute on function public.admin_update_feedback_report_v195(uuid, text, text, timestamp with time zone, uuid) to authenticated;
grant execute on function public.admin_update_feedback_report_v195(uuid, text, text, timestamp with time zone, uuid) to service_role;
revoke all on function public.admin_update_profile_v188(uuid, text, text, boolean) from public;
grant execute on function public.admin_update_profile_v188(uuid, text, text, boolean) to service_role;
revoke all on function public.apply_qr_lot_operation_v136(uuid, text, text, numeric, numeric, numeric, numeric, text, text, text, text, text, jsonb, jsonb, numeric, text, text) from public;
grant execute on function public.apply_qr_lot_operation_v136(uuid, text, text, numeric, numeric, numeric, numeric, text, text, text, text, text, jsonb, jsonb, numeric, text, text) to service_role;
revoke all on function public.apply_qr_lot_operation(uuid, text, text, numeric, numeric, numeric, numeric, text, text, text, text, text, jsonb, jsonb, numeric) from public;
grant execute on function public.apply_qr_lot_operation(uuid, text, text, numeric, numeric, numeric, numeric, text, text, text, text, text, jsonb, jsonb, numeric) to authenticated;
grant execute on function public.apply_qr_lot_operation(uuid, text, text, numeric, numeric, numeric, numeric, text, text, text, text, text, jsonb, jsonb, numeric) to service_role;
revoke all on function public.approve_fifo_mode_transition_v1136(uuid, text, boolean) from public;
grant execute on function public.approve_fifo_mode_transition_v1136(uuid, text, boolean) to service_role;
revoke all on function public.assert_app_state_not_rollback_v185(jsonb, jsonb, jsonb) from public;
grant execute on function public.assert_app_state_not_rollback_v185(jsonb, jsonb, jsonb) to anon;
grant execute on function public.assert_app_state_not_rollback_v185(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.assert_app_state_not_rollback_v185(jsonb, jsonb, jsonb) to service_role;
revoke all on function public.backup_app_state_before_update_v185() from public;
grant execute on function public.backup_app_state_before_update_v185() to service_role;
revoke all on function public.can_modify_app_state() from public;
grant execute on function public.can_modify_app_state() to authenticated;
grant execute on function public.can_modify_app_state() to service_role;
revoke all on function public.cancel_qr_inventory_session(uuid, uuid, text, text, jsonb, jsonb, text) from public;
grant execute on function public.cancel_qr_inventory_session(uuid, uuid, text, text, jsonb, jsonb, text) to authenticated;
grant execute on function public.cancel_qr_inventory_session(uuid, uuid, text, text, jsonb, jsonb, text) to service_role;
revoke all on function public.cancel_qr_lot_operation(uuid, uuid, text, text, jsonb, jsonb, text) from public;
grant execute on function public.cancel_qr_lot_operation(uuid, uuid, text, text, jsonb, jsonb, text) to authenticated;
grant execute on function public.cancel_qr_lot_operation(uuid, uuid, text, text, jsonb, jsonb, text) to service_role;
revoke all on function public.cancel_qr_quality_photo_upload_v1102(uuid) from public;
grant execute on function public.cancel_qr_quality_photo_upload_v1102(uuid) to authenticated;
grant execute on function public.cancel_qr_quality_photo_upload_v1102(uuid) to service_role;
revoke all on function public.cancel_trimming_job_legacy_v1144(uuid, uuid, text) from public;
grant execute on function public.cancel_trimming_job_legacy_v1144(uuid, uuid, text) to authenticated;
grant execute on function public.cancel_trimming_job_legacy_v1144(uuid, uuid, text) to service_role;
revoke all on function public.cancel_trimming_job(uuid, uuid, text) from public;
grant execute on function public.cancel_trimming_job(uuid, uuid, text) to authenticated;
grant execute on function public.cancel_trimming_job(uuid, uuid, text) to service_role;
revoke all on function public.capture_app_state_backup_v1167() from public;
grant execute on function public.capture_app_state_backup_v1167() to service_role;
revoke all on function public.carry_forward_market_prices_v1126(date, date) from public;
grant execute on function public.carry_forward_market_prices_v1126(date, date) to authenticated;
grant execute on function public.carry_forward_market_prices_v1126(date, date) to service_role;
revoke all on function public.claim_quality_push_jobs_v1144(text, integer) from public;
grant execute on function public.claim_quality_push_jobs_v1144(text, integer) to service_role;
revoke all on function public.cleanup_qr_lots() from public;
grant execute on function public.cleanup_qr_lots() to service_role;
revoke all on function public.complete_quality_push_job_v1144(uuid, text, text, text) from public;
grant execute on function public.complete_quality_push_job_v1144(uuid, text, text, text) to service_role;
revoke all on function public.confirm_monthly_archive_saved_v1101(text, date) from public;
grant execute on function public.confirm_monthly_archive_saved_v1101(text, date) to authenticated;
grant execute on function public.confirm_monthly_archive_saved_v1101(text, date) to service_role;
revoke all on function public.confirm_monthly_quality_archive_saved_v1102(date) from public;
grant execute on function public.confirm_monthly_quality_archive_saved_v1102(date) to authenticated;
grant execute on function public.confirm_monthly_quality_archive_saved_v1102(date) to service_role;
revoke all on function public.confirm_qr_inventory_session(uuid, uuid, text, jsonb, text, text, jsonb, jsonb) from public;
grant execute on function public.confirm_qr_inventory_session(uuid, uuid, text, jsonb, text, text, jsonb, jsonb) to service_role;
revoke all on function public.create_admin_notice_v1150(text, bigint, text, text, text, date, date, text) from public;
grant execute on function public.create_admin_notice_v1150(text, bigint, text, text, text, date, date, text) to service_role;
grant execute on function public.create_admin_notice_v1150(text, bigint, text, text, text, date, date, text) to authenticated;
revoke all on function public.create_manual_app_state_backup_v1167(text, uuid, text) from public;
grant execute on function public.create_manual_app_state_backup_v1167(text, uuid, text) to authenticated;
grant execute on function public.create_manual_app_state_backup_v1167(text, uuid, text) to service_role;
revoke all on function public.create_qr_lot_v185(jsonb, uuid, jsonb, jsonb) from public;
grant execute on function public.create_qr_lot_v185(jsonb, uuid, jsonb, jsonb) to authenticated;
grant execute on function public.create_qr_lot_v185(jsonb, uuid, jsonb, jsonb) to service_role;
revoke all on function public.create_qr_quality_evaluation_v1102(text, text, text[], text, text, uuid, timestamp with time zone) from public;
grant execute on function public.create_qr_quality_evaluation_v1102(text, text, text[], text, text, uuid, timestamp with time zone) to authenticated;
grant execute on function public.create_qr_quality_evaluation_v1102(text, text, text[], text, text, uuid, timestamp with time zone) to service_role;
revoke all on function public.create_qr_quality_photo_upload_v1102(uuid, text, text, bigint) from public;
grant execute on function public.create_qr_quality_photo_upload_v1102(uuid, text, text, bigint) to authenticated;
grant execute on function public.create_qr_quality_photo_upload_v1102(uuid, text, text, bigint) to service_role;
revoke all on function public.create_trimming_job(uuid, date, jsonb, jsonb, text, text) from public;
grant execute on function public.create_trimming_job(uuid, date, jsonb, jsonb, text, text) to authenticated;
grant execute on function public.create_trimming_job(uuid, date, jsonb, jsonb, text, text) to service_role;
revoke all on function public.current_app_role() from public;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.current_app_role() to service_role;
revoke all on function public.delete_admin_notice_v1150(text, bigint, text, text) from public;
grant execute on function public.delete_admin_notice_v1150(text, bigint, text, text) to service_role;
grant execute on function public.delete_admin_notice_v1150(text, bigint, text, text) to authenticated;
revoke all on function public.delete_clerk_waste_v188(text, bigint, text, text, jsonb, jsonb) from public;
grant execute on function public.delete_clerk_waste_v188(text, bigint, text, text, jsonb, jsonb) to authenticated;
grant execute on function public.delete_clerk_waste_v188(text, bigint, text, text, jsonb, jsonb) to service_role;
revoke all on function public.delete_qr_lot_v182(text, uuid, text) from public;
grant execute on function public.delete_qr_lot_v182(text, uuid, text) to service_role;
revoke all on function public.delete_trimming_job_v1203(text) from public;
grant execute on function public.delete_trimming_job_v1203(text) to authenticated;
grant execute on function public.delete_trimming_job_v1203(text) to service_role;
revoke all on function public.disable_my_push_subscription_v1144(text) from public;
grant execute on function public.disable_my_push_subscription_v1144(text) to authenticated;
grant execute on function public.disable_my_push_subscription_v1144(text) to service_role;
revoke all on function public.finalize_monthly_quality_purge_v1102(date) from public;
grant execute on function public.finalize_monthly_quality_purge_v1102(date) to authenticated;
grant execute on function public.finalize_monthly_quality_purge_v1102(date) to service_role;
revoke all on function public.finalize_monthly_quality_purge_v1166(date) from public;
grant execute on function public.finalize_monthly_quality_purge_v1166(date) to authenticated;
grant execute on function public.finalize_monthly_quality_purge_v1166(date) to service_role;
revoke all on function public.finalize_qr_quality_photo_upload_v1102(uuid) from public;
grant execute on function public.finalize_qr_quality_photo_upload_v1102(uuid) to authenticated;
grant execute on function public.finalize_qr_quality_photo_upload_v1102(uuid) to service_role;
revoke all on function public.finalize_qr_waste_price_v1118(uuid, text, numeric) from public;
grant execute on function public.finalize_qr_waste_price_v1118(uuid, text, numeric) to authenticated;
grant execute on function public.finalize_qr_waste_price_v1118(uuid, text, numeric) to service_role;
revoke all on function public.get_app_state_v187(text) from public;
grant execute on function public.get_app_state_v187(text) to authenticated;
grant execute on function public.get_app_state_v187(text) to service_role;
revoke all on function public.get_fifo_candidates_v1136(text, integer) from public;
grant execute on function public.get_fifo_candidates_v1136(text, integer) to service_role;
revoke all on function public.get_inventory_loss_cockpit_v1136(date, date) from public;
grant execute on function public.get_inventory_loss_cockpit_v1136(date, date) to service_role;
revoke all on function public.get_monthly_quality_export_v1102(date) from public;
grant execute on function public.get_monthly_quality_export_v1102(date) to authenticated;
grant execute on function public.get_monthly_quality_export_v1102(date) to service_role;
revoke all on function public.get_monthly_trimming_archive_v1116(date) from public;
grant execute on function public.get_monthly_trimming_archive_v1116(date) to authenticated;
grant execute on function public.get_monthly_trimming_archive_v1116(date) to service_role;
revoke all on function public.get_my_profile() from public;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.get_my_profile() to service_role;
revoke all on function public.get_purchase_prices(date) from public;
grant execute on function public.get_purchase_prices(date) to authenticated;
grant execute on function public.get_purchase_prices(date) to service_role;
revoke all on function public.get_push_notification_config_v1144() from public;
grant execute on function public.get_push_notification_config_v1144() to authenticated;
grant execute on function public.get_push_notification_config_v1144() to service_role;
revoke all on function public.get_rule_based_decisions_v1136(integer) from public;
grant execute on function public.get_rule_based_decisions_v1136(integer) to service_role;
revoke all on function public.get_seika_v1136_settings() from public;
grant execute on function public.get_seika_v1136_settings() to service_role;
revoke all on function public.get_supplier_quality_analysis_v1136(date, date, text) from public;
grant execute on function public.get_supplier_quality_analysis_v1136(date, date, text) to service_role;
revoke all on function public.get_trimming_jobs(date, date) from public;
grant execute on function public.get_trimming_jobs(date, date) to authenticated;
grant execute on function public.get_trimming_jobs(date, date) to service_role;
revoke all on function public.guard_app_state_update_v185() from public;
grant execute on function public.guard_app_state_update_v185() to anon;
grant execute on function public.guard_app_state_update_v185() to authenticated;
grant execute on function public.guard_app_state_update_v185() to service_role;
revoke all on function public.guard_seika_qr_write_v187() from public;
grant execute on function public.guard_seika_qr_write_v187() to service_role;
revoke all on function public.has_any_role(text[]) from public;
grant execute on function public.has_any_role(text[]) to authenticated;
grant execute on function public.has_any_role(text[]) to service_role;
revoke all on function public.is_active_user() from public;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_active_user() to service_role;
revoke all on function public.list_active_registered_users_v1178() from public;
grant execute on function public.list_active_registered_users_v1178() to authenticated;
grant execute on function public.list_active_registered_users_v1178() to service_role;
revoke all on function public.list_active_registered_users_v1179() from public;
grant execute on function public.list_active_registered_users_v1179() to authenticated;
grant execute on function public.list_active_registered_users_v1179() to service_role;
revoke all on function public.list_monthly_archives_v1101(text) from public;
grant execute on function public.list_monthly_archives_v1101(text) to authenticated;
grant execute on function public.list_monthly_archives_v1101(text) to service_role;
revoke all on function public.list_monthly_quality_archives_v1102() from public;
grant execute on function public.list_monthly_quality_archives_v1102() to authenticated;
grant execute on function public.list_monthly_quality_archives_v1102() to service_role;
revoke all on function public.list_monthly_quality_archives_v1166() from public;
grant execute on function public.list_monthly_quality_archives_v1166() to authenticated;
grant execute on function public.list_monthly_quality_archives_v1166() to service_role;
revoke all on function public.list_my_unacknowledged_low_quality_evaluations_v1103(integer) from public;
grant execute on function public.list_my_unacknowledged_low_quality_evaluations_v1103(integer) to authenticated;
grant execute on function public.list_my_unacknowledged_low_quality_evaluations_v1103(integer) to service_role;
revoke all on function public.list_qr_outbound_history_v1144(text, date, boolean, integer, integer) from public;
grant execute on function public.list_qr_outbound_history_v1144(text, date, boolean, integer, integer) to authenticated;
grant execute on function public.list_qr_outbound_history_v1144(text, date, boolean, integer, integer) to service_role;
revoke all on function public.list_qr_quality_evaluations_v1102(text) from public;
grant execute on function public.list_qr_quality_evaluations_v1102(text) to authenticated;
grant execute on function public.list_qr_quality_evaluations_v1102(text) to service_role;
revoke all on function public.list_qr_quality_evaluations_v1103(date, text, text, text, boolean, integer, integer) from public;
grant execute on function public.list_qr_quality_evaluations_v1103(date, text, text, text, boolean, integer, integer) to authenticated;
grant execute on function public.list_qr_quality_evaluations_v1103(date, text, text, text, boolean, integer, integer) to service_role;
revoke all on function public.list_qr_quality_evaluations_v1158(date, text, text, text, boolean, text, integer, integer) from public;
grant execute on function public.list_qr_quality_evaluations_v1158(date, text, text, text, boolean, text, integer, integer) to authenticated;
grant execute on function public.list_qr_quality_evaluations_v1158(date, text, text, text, boolean, text, integer, integer) to service_role;
revoke all on function public.list_qr_quality_evaluations_v1159(date, text, text, text, boolean, text, integer, integer) from public;
grant execute on function public.list_qr_quality_evaluations_v1159(date, text, text, text, boolean, text, integer, integer) to authenticated;
grant execute on function public.list_qr_quality_evaluations_v1159(date, text, text, text, boolean, text, integer, integer) to service_role;
revoke all on function public.list_unified_waste_records_v1144(date, date) from public;
grant execute on function public.list_unified_waste_records_v1144(date, date) to authenticated;
grant execute on function public.list_unified_waste_records_v1144(date, date) to service_role;
revoke all on function public.mark_monthly_archive_created_v1101(text, date, text, bigint) from public;
grant execute on function public.mark_monthly_archive_created_v1101(text, date, text, bigint) to authenticated;
grant execute on function public.mark_monthly_archive_created_v1101(text, date, text, bigint) to service_role;
revoke all on function public.mark_monthly_quality_archive_created_v1102(date, text, bigint, bigint) from public;
grant execute on function public.mark_monthly_quality_archive_created_v1102(date, text, bigint, bigint) to authenticated;
grant execute on function public.mark_monthly_quality_archive_created_v1102(date, text, bigint, bigint) to service_role;
revoke all on function public.prepare_monthly_quality_purge_v1102(date) from public;
grant execute on function public.prepare_monthly_quality_purge_v1102(date) to authenticated;
grant execute on function public.prepare_monthly_quality_purge_v1102(date) to service_role;
revoke all on function public.prepare_monthly_quality_purge_v1166(date) from public;
grant execute on function public.prepare_monthly_quality_purge_v1166(date) to authenticated;
grant execute on function public.prepare_monthly_quality_purge_v1166(date) to service_role;
revoke all on function public.purge_monthly_archive_v1101(text, date) from public;
grant execute on function public.purge_monthly_archive_v1101(text, date) to authenticated;
grant execute on function public.purge_monthly_archive_v1101(text, date) to service_role;
revoke all on function public.qr_inventory_entry_operation_id(uuid, text) from public;
grant execute on function public.qr_inventory_entry_operation_id(uuid, text) to anon;
grant execute on function public.qr_inventory_entry_operation_id(uuid, text) to authenticated;
grant execute on function public.qr_inventory_entry_operation_id(uuid, text) to service_role;
revoke all on function public.qr_lot_daily_state_v1211(date, date) from public;
grant execute on function public.qr_lot_daily_state_v1211(date, date) to authenticated;
grant execute on function public.qr_lot_daily_state_v1211(date, date) to service_role;
revoke all on function public.recalc_trimming_job_price_v1195(uuid) from public;
grant execute on function public.recalc_trimming_job_price_v1195(uuid) to authenticated;
grant execute on function public.recalc_trimming_job_price_v1195(uuid) to service_role;
revoke all on function public.recalculate_qr_waste_price_v1162(uuid, numeric, text) from public;
grant execute on function public.recalculate_qr_waste_price_v1162(uuid, numeric, text) to authenticated;
grant execute on function public.recalculate_qr_waste_price_v1162(uuid, numeric, text) to service_role;
revoke all on function public.replace_trimming_job_outputs(uuid, jsonb) from public;
grant execute on function public.replace_trimming_job_outputs(uuid, jsonb) to authenticated;
grant execute on function public.replace_trimming_job_outputs(uuid, jsonb) to service_role;
revoke all on function public.replace_trimming_job_v1203(text, text, text, jsonb, jsonb, text, text) from public;
grant execute on function public.replace_trimming_job_v1203(text, text, text, jsonb, jsonb, text, text) to authenticated;
grant execute on function public.replace_trimming_job_v1203(text, text, text, jsonb, jsonb, text, text) to service_role;
revoke all on function public.request_fifo_mode_transition_v1136(text, text, boolean) from public;
grant execute on function public.request_fifo_mode_transition_v1136(text, text, boolean) to service_role;
revoke all on function public.resolve_trimming_purchase_price_v1117(text, text, text, date) from public;
grant execute on function public.resolve_trimming_purchase_price_v1117(text, text, text, date) to authenticated;
grant execute on function public.resolve_trimming_purchase_price_v1117(text, text, text, date) to service_role;
revoke all on function public.resolve_waste_purchase_price_v1118(text, text, text, date) from public;
grant execute on function public.resolve_waste_purchase_price_v1118(text, text, text, date) to authenticated;
grant execute on function public.resolve_waste_purchase_price_v1118(text, text, text, date) to service_role;
revoke all on function public.save_admin_notices_v1147(text, bigint, jsonb, jsonb, text) from public;
grant execute on function public.save_admin_notices_v1147(text, bigint, jsonb, jsonb, text) to service_role;
revoke all on function public.save_clerk_waste_history_v188(jsonb) from public;
grant execute on function public.save_clerk_waste_history_v188(jsonb) to authenticated;
grant execute on function public.save_clerk_waste_history_v188(jsonb) to service_role;
revoke all on function public.save_clerk_waste_state_v188(text, bigint, jsonb, jsonb, text, jsonb, jsonb) from public;
grant execute on function public.save_clerk_waste_state_v188(text, bigint, jsonb, jsonb, text, jsonb, jsonb) to authenticated;
grant execute on function public.save_clerk_waste_state_v188(text, bigint, jsonb, jsonb, text, jsonb, jsonb) to service_role;
revoke all on function public.save_history_records_v188(jsonb, jsonb, jsonb, text[], text[], text[]) from public;
grant execute on function public.save_history_records_v188(jsonb, jsonb, jsonb, text[], text[], text[]) to authenticated;
grant execute on function public.save_history_records_v188(jsonb, jsonb, jsonb, text[], text[], text[]) to service_role;
revoke all on function public.save_qr_lot_edit_history_v1158(uuid, jsonb) from public;
grant execute on function public.save_qr_lot_edit_history_v1158(uuid, jsonb) to authenticated;
grant execute on function public.save_qr_lot_edit_history_v1158(uuid, jsonb) to service_role;
revoke all on function public.save_qr_lot_edit_history_v1159(uuid, jsonb) from public;
grant execute on function public.save_qr_lot_edit_history_v1159(uuid, jsonb) to authenticated;
grant execute on function public.save_qr_lot_edit_history_v1159(uuid, jsonb) to service_role;
revoke all on function public.seika_admin_notice_audit_guard_v1150() from public;
grant execute on function public.seika_admin_notice_audit_guard_v1150() to service_role;
revoke all on function public.seika_admin_notice_require_admin_v1150() from public;
grant execute on function public.seika_admin_notice_require_admin_v1150() to service_role;
revoke all on function public.seika_admin_notice_sync_app_state_v1150(text) from public;
grant execute on function public.seika_admin_notice_sync_app_state_v1150(text) to service_role;
revoke all on function public.seika_archive_module_allowed_v1101(text, text) from public;
grant execute on function public.seika_archive_module_allowed_v1101(text, text) to service_role;
revoke all on function public.seika_archive_profile_v1101() from public;
grant execute on function public.seika_archive_profile_v1101() to service_role;
revoke all on function public.seika_current_profile_v1145() from public;
grant execute on function public.seika_current_profile_v1145() to service_role;
revoke all on function public.seika_delete_trimming_job_rows_v1203(text) from public;
grant execute on function public.seika_delete_trimming_job_rows_v1203(text) to authenticated;
grant execute on function public.seika_delete_trimming_job_rows_v1203(text) to service_role;
revoke all on function public.seika_enqueue_low_quality_push_v1144() from public;
grant execute on function public.seika_enqueue_low_quality_push_v1144() to authenticated;
grant execute on function public.seika_enqueue_low_quality_push_v1144() to service_role;
revoke all on function public.seika_fifo_assess_lot_v1136(text) from public;
grant execute on function public.seika_fifo_assess_lot_v1136(text) to service_role;
revoke all on function public.seika_guard_old_waste_delete_v1101() from public;
grant execute on function public.seika_guard_old_waste_delete_v1101() to service_role;
revoke all on function public.seika_inventory_count_decimal_optional_v123(text, text) from public;
grant execute on function public.seika_inventory_count_decimal_optional_v123(text, text) to service_role;
revoke all on function public.seika_inventory_count_decimal_v1119(text, text) from public;
grant execute on function public.seika_inventory_count_decimal_v1119(text, text) to service_role;
revoke all on function public.seika_inventory_count_line_kg_v1119(jsonb, boolean) from public;
grant execute on function public.seika_inventory_count_line_kg_v1119(jsonb, boolean) to service_role;
revoke all on function public.seika_inventory_count_lock_v1119(text, bigint) from public;
grant execute on function public.seika_inventory_count_lock_v1119(text, bigint) to service_role;
revoke all on function public.seika_inventory_count_normalize_session_v123(jsonb) from public;
grant execute on function public.seika_inventory_count_normalize_session_v123(jsonb) to service_role;
revoke all on function public.seika_inventory_count_normalize_session_v124(jsonb) from public;
grant execute on function public.seika_inventory_count_normalize_session_v124(jsonb) to service_role;
revoke all on function public.seika_inventory_count_profile_v1119() from public;
grant execute on function public.seika_inventory_count_profile_v1119() to service_role;
revoke all on function public.seika_inventory_count_profile_v123() from public;
grant execute on function public.seika_inventory_count_profile_v123() to service_role;
revoke all on function public.seika_inventory_count_replace_session_v1119(jsonb, text, jsonb) from public;
grant execute on function public.seika_inventory_count_replace_session_v1119(jsonb, text, jsonb) to service_role;
revoke all on function public.seika_inventory_count_session_v1119(jsonb, text) from public;
grant execute on function public.seika_inventory_count_session_v1119(jsonb, text) to service_role;
revoke all on function public.seika_inventory_count_v123_append_log(jsonb, jsonb) from public;
grant execute on function public.seika_inventory_count_v123_append_log(jsonb, jsonb) to service_role;
revoke all on function public.seika_inventory_count_v123_replace_session(jsonb, text, jsonb) from public;
grant execute on function public.seika_inventory_count_v123_replace_session(jsonb, text, jsonb) to service_role;
revoke all on function public.seika_inventory_count_v123_status(jsonb) from public;
grant execute on function public.seika_inventory_count_v123_status(jsonb) to service_role;
revoke all on function public.seika_inventory_count_v124_prices_complete(jsonb) from public;
grant execute on function public.seika_inventory_count_v124_prices_complete(jsonb) to service_role;
revoke all on function public.seika_inventory_count_v124_section_rows(jsonb, text) from public;
grant execute on function public.seika_inventory_count_v124_section_rows(jsonb, text) to service_role;
revoke all on function public.seika_inventory_count_v124_status(jsonb) from public;
grant execute on function public.seika_inventory_count_v124_status(jsonb) to service_role;
revoke all on function public.seika_inventory_count_v124_trim_operations(jsonb) from public;
grant execute on function public.seika_inventory_count_v124_trim_operations(jsonb) to service_role;
revoke all on function public.seika_item_name_group_v1200(text) from public;
grant execute on function public.seika_item_name_group_v1200(text) to anon;
grant execute on function public.seika_item_name_group_v1200(text) to authenticated;
grant execute on function public.seika_item_name_group_v1200(text) to service_role;
revoke all on function public.seika_mark_password_changed_v1202() from public;
grant execute on function public.seika_mark_password_changed_v1202() to authenticated;
grant execute on function public.seika_mark_password_changed_v1202() to service_role;
revoke all on function public.seika_parse_kg_v1162(text) from public;
grant execute on function public.seika_parse_kg_v1162(text) to service_role;
revoke all on function public.seika_permission_diagnostics_v1145() from public;
grant execute on function public.seika_permission_diagnostics_v1145() to authenticated;
grant execute on function public.seika_permission_diagnostics_v1145() to service_role;
revoke all on function public.seika_purge_old_inventory_counts_v1205(text) from public;
grant execute on function public.seika_purge_old_inventory_counts_v1205(text) to authenticated;
grant execute on function public.seika_purge_old_inventory_counts_v1205(text) to service_role;
revoke all on function public.seika_qr_block_lot_hard_delete_v1119() from public;
grant execute on function public.seika_qr_block_lot_hard_delete_v1119() to anon;
grant execute on function public.seika_qr_block_lot_hard_delete_v1119() to authenticated;
grant execute on function public.seika_qr_block_lot_hard_delete_v1119() to service_role;
revoke all on function public.seika_qr_guard_lot_soft_delete_v1119() from public;
grant execute on function public.seika_qr_guard_lot_soft_delete_v1119() to anon;
grant execute on function public.seika_qr_guard_lot_soft_delete_v1119() to authenticated;
grant execute on function public.seika_qr_guard_lot_soft_delete_v1119() to service_role;
revoke all on function public.seika_qr_guard_quality_invalidation_v1119() from public;
grant execute on function public.seika_qr_guard_quality_invalidation_v1119() to anon;
grant execute on function public.seika_qr_guard_quality_invalidation_v1119() to authenticated;
grant execute on function public.seika_qr_guard_quality_invalidation_v1119() to service_role;
revoke all on function public.seika_qr_guard_quality_photo_invalidation_v1119() from public;
grant execute on function public.seika_qr_guard_quality_photo_invalidation_v1119() to anon;
grant execute on function public.seika_qr_guard_quality_photo_invalidation_v1119() to authenticated;
grant execute on function public.seika_qr_guard_quality_photo_invalidation_v1119() to service_role;
revoke all on function public.seika_qr_operation_cancelled_v1162(text) from public;
grant execute on function public.seika_qr_operation_cancelled_v1162(text) to service_role;
revoke all on function public.seika_quality_archive_after_photo_finalize_v1102() from public;
grant execute on function public.seika_quality_archive_after_photo_finalize_v1102() to anon;
grant execute on function public.seika_quality_archive_after_photo_finalize_v1102() to authenticated;
grant execute on function public.seika_quality_archive_after_photo_finalize_v1102() to service_role;
revoke all on function public.seika_quality_archive_before_insert_v1102() from public;
grant execute on function public.seika_quality_archive_before_insert_v1102() to anon;
grant execute on function public.seika_quality_archive_before_insert_v1102() to authenticated;
grant execute on function public.seika_quality_archive_before_insert_v1102() to service_role;
revoke all on function public.seika_quality_archive_invalidate_v1102(date) from public;
grant execute on function public.seika_quality_archive_invalidate_v1102(date) to service_role;
revoke all on function public.seika_quality_buyer_context_for_item_v1144(uuid, text) from public;
grant execute on function public.seika_quality_buyer_context_for_item_v1144(uuid, text) to service_role;
revoke all on function public.seika_quality_buyer_context_for_lot_v1144(uuid) from public;
grant execute on function public.seika_quality_buyer_context_for_lot_v1144(uuid) to service_role;
revoke all on function public.seika_quality_buyer_context_for_lot_v1159(uuid) from public;
grant execute on function public.seika_quality_buyer_context_for_lot_v1159(uuid) to service_role;
revoke all on function public.seika_quality_buyers_for_item_v1103(text) from public;
grant execute on function public.seika_quality_buyers_for_item_v1103(text) to service_role;
revoke all on function public.seika_quality_can_operate_v1102() from public;
grant execute on function public.seika_quality_can_operate_v1102() to service_role;
grant execute on function public.seika_quality_can_operate_v1102() to authenticated;
revoke all on function public.seika_quality_month_v1102(timestamp with time zone) from public;
grant execute on function public.seika_quality_month_v1102(timestamp with time zone) to service_role;
revoke all on function public.seika_quality_monthly_storage_delete_allowed_v1102(text) from public;
grant execute on function public.seika_quality_monthly_storage_delete_allowed_v1102(text) to service_role;
grant execute on function public.seika_quality_monthly_storage_delete_allowed_v1102(text) to authenticated;
revoke all on function public.seika_quality_monthly_storage_delete_allowed_v1166(text) from public;
grant execute on function public.seika_quality_monthly_storage_delete_allowed_v1166(text) to authenticated;
grant execute on function public.seika_quality_monthly_storage_delete_allowed_v1166(text) to service_role;
revoke all on function public.seika_quality_profile_v1102() from public;
grant execute on function public.seika_quality_profile_v1102() to service_role;
grant execute on function public.seika_quality_profile_v1102() to authenticated;
revoke all on function public.seika_quality_push_my_profile_v1144() from public;
grant execute on function public.seika_quality_push_my_profile_v1144() to service_role;
revoke all on function public.seika_quality_upload_path_allowed_v1102(text) from public;
grant execute on function public.seika_quality_upload_path_allowed_v1102(text) to service_role;
grant execute on function public.seika_quality_upload_path_allowed_v1102(text) to authenticated;
revoke all on function public.seika_uuid_v188(text) from public;
grant execute on function public.seika_uuid_v188(text) to service_role;
revoke all on function public.seika_v1136_active_profile() from public;
grant execute on function public.seika_v1136_active_profile() to service_role;
revoke all on function public.seika_v1136_get_fifo_mode() from public;
grant execute on function public.seika_v1136_get_fifo_mode() to service_role;
revoke all on function public.seika_v1136_require_roles(text[]) from public;
grant execute on function public.seika_v1136_require_roles(text[]) to service_role;
revoke all on function public.seika_v1144_fill_purchase_staff_identity() from public;
grant execute on function public.seika_v1144_fill_purchase_staff_identity() to service_role;
revoke all on function public.seika_v1144_item_name_master_legacy_user_id(text) from public;
grant execute on function public.seika_v1144_item_name_master_legacy_user_id(text) to service_role;
revoke all on function public.seika_v1144_normalize_item_name(text) from public;
grant execute on function public.seika_v1144_normalize_item_name(text) to service_role;
revoke all on function public.seika_v1144_profile_by_legacy_user_id(text) from public;
grant execute on function public.seika_v1144_profile_by_legacy_user_id(text) to service_role;
revoke all on function public.seika_v1144_profile_for_purchase_staff_name(text) from public;
grant execute on function public.seika_v1144_profile_for_purchase_staff_name(text) to service_role;
revoke all on function public.seika_v1144_qr_operation_cancelled(text) from public;
grant execute on function public.seika_v1144_qr_operation_cancelled(text) to service_role;
revoke all on function public.seika_v1144_qr_operation_cancelled(uuid) from public;
grant execute on function public.seika_v1144_qr_operation_cancelled(uuid) to service_role;
revoke all on function public.seika_v1144_require_active_profile() from public;
grant execute on function public.seika_v1144_require_active_profile() to service_role;
revoke all on function public.seika_v1144_resolve_quality_lot(text, text) from public;
grant execute on function public.seika_v1144_resolve_quality_lot(text, text) to service_role;
revoke all on function public.seika_v1159_qr_operator() from public;
grant execute on function public.seika_v1159_qr_operator() to service_role;
revoke all on function public.set_admin_notice_active_v1150(text, bigint, text, boolean, text) from public;
grant execute on function public.set_admin_notice_active_v1150(text, bigint, text, boolean, text) to service_role;
grant execute on function public.set_admin_notice_active_v1150(text, bigint, text, boolean, text) to authenticated;
revoke all on function public.set_fifo_lot_hold_v1136(uuid, boolean, text) from public;
grant execute on function public.set_fifo_lot_hold_v1136(uuid, boolean, text) to service_role;
revoke all on function public.set_seika_feature_mode_v1136(text, text) from public;
grant execute on function public.set_seika_feature_mode_v1136(text, text) to service_role;
revoke all on function public.set_updated_at() from public;
grant execute on function public.set_updated_at() to anon;
grant execute on function public.set_updated_at() to authenticated;
grant execute on function public.set_updated_at() to service_role;
revoke all on function public.soft_delete_mistaken_qr_lot_v1119(text, text) from public;
grant execute on function public.soft_delete_mistaken_qr_lot_v1119(text, text) to authenticated;
grant execute on function public.soft_delete_mistaken_qr_lot_v1119(text, text) to service_role;
revoke all on function public.submit_feedback_report_v195(text, text, text, text, uuid) from public;
grant execute on function public.submit_feedback_report_v195(text, text, text, text, uuid) to authenticated;
grant execute on function public.submit_feedback_report_v195(text, text, text, text, uuid) to service_role;
revoke all on function public.trimming_is_market_supplier_v1117(text) from public;
grant execute on function public.trimming_is_market_supplier_v1117(text) to authenticated;
grant execute on function public.trimming_is_market_supplier_v1117(text) to service_role;
revoke all on function public.trimming_lock_inventory_state() from public;
grant execute on function public.trimming_lock_inventory_state() to authenticated;
grant execute on function public.trimming_lock_inventory_state() to service_role;
revoke all on function public.trimming_normalize_supplier_v1117(text) from public;
grant execute on function public.trimming_normalize_supplier_v1117(text) to authenticated;
grant execute on function public.trimming_normalize_supplier_v1117(text) to service_role;
revoke all on function public.trimming_require_role(text[]) from public;
grant execute on function public.trimming_require_role(text[]) to service_role;
revoke all on function public.trimming_week_start(date) from public;
grant execute on function public.trimming_week_start(date) to authenticated;
grant execute on function public.trimming_week_start(date) to service_role;
revoke all on function public.update_app_state_if_version_v187(text, bigint, jsonb, text, jsonb, jsonb) from public;
grant execute on function public.update_app_state_if_version_v187(text, bigint, jsonb, text, jsonb, jsonb) to authenticated;
grant execute on function public.update_app_state_if_version_v187(text, bigint, jsonb, text, jsonb, jsonb) to service_role;
revoke all on function public.update_app_state_if_version(text, bigint, jsonb, uuid, jsonb, jsonb) from public;
grant execute on function public.update_app_state_if_version(text, bigint, jsonb, uuid, jsonb, jsonb) to service_role;
revoke all on function public.update_app_state_partial_v188(text, bigint, jsonb, text, jsonb, jsonb) from public;
grant execute on function public.update_app_state_partial_v188(text, bigint, jsonb, text, jsonb, jsonb) to authenticated;
grant execute on function public.update_app_state_partial_v188(text, bigint, jsonb, text, jsonb, jsonb) to service_role;
revoke all on function public.update_purchase_price_v1127(date, text, text, text, date, text, text, text, numeric, text) from public;
grant execute on function public.update_purchase_price_v1127(date, text, text, text, date, text, text, text, numeric, text) to authenticated;
grant execute on function public.update_purchase_price_v1127(date, text, text, text, date, text, text, text, numeric, text) to service_role;
revoke all on function public.update_trimming_job_work_date_v1197(uuid, date) from public;
grant execute on function public.update_trimming_job_work_date_v1197(uuid, date) to authenticated;
grant execute on function public.update_trimming_job_work_date_v1197(uuid, date) to service_role;
revoke all on function public.upsert_item_aging_policy_v1136(uuid, text, text, boolean, integer, integer, integer, boolean, boolean, date, date, text) from public;
grant execute on function public.upsert_item_aging_policy_v1136(uuid, text, text, boolean, integer, integer, integer, boolean, boolean, date, date, text) to service_role;
revoke all on function public.upsert_my_push_subscription_v1144(text, text, text, text, text) from public;
grant execute on function public.upsert_my_push_subscription_v1144(text, text, text, text, text) to authenticated;
grant execute on function public.upsert_my_push_subscription_v1144(text, text, text, text, text) to service_role;
revoke all on function public.upsert_purchase_price_v1117(date, text, text, text, numeric, text) from public;
grant execute on function public.upsert_purchase_price_v1117(date, text, text, text, numeric, text) to authenticated;
grant execute on function public.upsert_purchase_price_v1117(date, text, text, text, numeric, text) to service_role;
revoke all on function public.upsert_purchase_price(date, text, text, text, numeric) from public;
grant execute on function public.upsert_purchase_price(date, text, text, text, numeric) to authenticated;
grant execute on function public.upsert_purchase_price(date, text, text, text, numeric) to service_role;
revoke all on function public.v119_confirm_inventory_count_document(text, bigint, text, text) from public;
grant execute on function public.v119_confirm_inventory_count_document(text, bigint, text, text) to service_role;
revoke all on function public.v119_mark_inventory_count_excel_export(text, bigint, text, text) from public;
grant execute on function public.v119_mark_inventory_count_excel_export(text, bigint, text, text) to service_role;
revoke all on function public.v119_purge_inventory_count_details(text, bigint, text) from public;
grant execute on function public.v119_purge_inventory_count_details(text, bigint, text) to service_role;
revoke all on function public.v119_save_inventory_count_prices(text, bigint, text, jsonb) from public;
grant execute on function public.v119_save_inventory_count_prices(text, bigint, text, jsonb) to service_role;
revoke all on function public.v120_confirm_inventory_count_test(text, bigint, text) from public;
grant execute on function public.v120_confirm_inventory_count_test(text, bigint, text) to service_role;
revoke all on function public.v120_delete_unconfirmed_inventory_count(text, bigint, text, text) from public;
grant execute on function public.v120_delete_unconfirmed_inventory_count(text, bigint, text, text) to service_role;
revoke all on function public.v123_create_inventory_count_session(text, jsonb, text) from public;
grant execute on function public.v123_create_inventory_count_session(text, jsonb, text) to service_role;
revoke all on function public.v123_return_inventory_count_section(text, text, text, bigint) from public;
grant execute on function public.v123_return_inventory_count_section(text, text, text, bigint) to service_role;
revoke all on function public.v123_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) from public;
grant execute on function public.v123_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) to service_role;
revoke all on function public.v124_confirm_inventory_count_section(text, text, text, bigint, text) from public;
grant execute on function public.v124_confirm_inventory_count_section(text, text, text, bigint, text) to service_role;
revoke all on function public.v124_mark_inventory_count_excel_export(text, bigint, jsonb, text, text) from public;
grant execute on function public.v124_mark_inventory_count_excel_export(text, bigint, jsonb, text, text) to service_role;
revoke all on function public.v124_purge_inventory_count_details(text, bigint, text) from public;
grant execute on function public.v124_purge_inventory_count_details(text, bigint, text) to service_role;
revoke all on function public.v124_return_inventory_count_section(text, text, text, bigint, text) from public;
grant execute on function public.v124_return_inventory_count_section(text, text, text, bigint, text) to service_role;
revoke all on function public.v124_save_inventory_count_prices(text, bigint, text, jsonb) from public;
grant execute on function public.v124_save_inventory_count_prices(text, bigint, text, jsonb) to service_role;
revoke all on function public.v124_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) from public;
grant execute on function public.v124_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) to service_role;
revoke all on function public.v171_complete_simple_inventory_count_session(text, text, bigint, text) from public;
grant execute on function public.v171_complete_simple_inventory_count_session(text, text, bigint, text) to authenticated;
grant execute on function public.v171_complete_simple_inventory_count_session(text, text, bigint, text) to service_role;
revoke all on function public.v171_create_simple_inventory_count_session(text, jsonb, text) from public;
grant execute on function public.v171_create_simple_inventory_count_session(text, jsonb, text) to authenticated;
grant execute on function public.v171_create_simple_inventory_count_session(text, jsonb, text) to service_role;
revoke all on function public.v171_save_simple_inventory_count_section(text, text, text, bigint, jsonb, text, text) from public;
grant execute on function public.v171_save_simple_inventory_count_section(text, text, text, bigint, jsonb, text, text) to authenticated;
grant execute on function public.v171_save_simple_inventory_count_section(text, text, text, bigint, jsonb, text, text) to service_role;
revoke all on function public.v177_apply_inventory_count_session(text, text, bigint, text, jsonb, jsonb) from public;
grant execute on function public.v177_apply_inventory_count_session(text, text, bigint, text, jsonb, jsonb) to authenticated;
grant execute on function public.v177_apply_inventory_count_session(text, text, bigint, text, jsonb, jsonb) to service_role;
revoke all on function public.v177_create_inventory_count_session(text, jsonb, text) from public;
grant execute on function public.v177_create_inventory_count_session(text, jsonb, text) to authenticated;
grant execute on function public.v177_create_inventory_count_session(text, jsonb, text) to service_role;
revoke all on function public.v177_delete_legacy_inventory_count_sessions(text, bigint, jsonb) from public;
grant execute on function public.v177_delete_legacy_inventory_count_sessions(text, bigint, jsonb) to authenticated;
grant execute on function public.v177_delete_legacy_inventory_count_sessions(text, bigint, jsonb) to service_role;
revoke all on function public.v177_inventory_sessions(jsonb) from public;
grant execute on function public.v177_inventory_sessions(jsonb) to anon;
grant execute on function public.v177_inventory_sessions(jsonb) to authenticated;
grant execute on function public.v177_inventory_sessions(jsonb) to service_role;
revoke all on function public.v177_parse_bigint(text, text, bigint) from public;
grant execute on function public.v177_parse_bigint(text, text, bigint) to anon;
grant execute on function public.v177_parse_bigint(text, text, bigint) to authenticated;
grant execute on function public.v177_parse_bigint(text, text, bigint) to service_role;
revoke all on function public.v177_parse_boolean(text, text, boolean) from public;
grant execute on function public.v177_parse_boolean(text, text, boolean) to anon;
grant execute on function public.v177_parse_boolean(text, text, boolean) to authenticated;
grant execute on function public.v177_parse_boolean(text, text, boolean) to service_role;
revoke all on function public.v177_parse_decimal(text, text, boolean) from public;
grant execute on function public.v177_parse_decimal(text, text, boolean) to anon;
grant execute on function public.v177_parse_decimal(text, text, boolean) to authenticated;
grant execute on function public.v177_parse_decimal(text, text, boolean) to service_role;
revoke all on function public.v177_require_json_array(jsonb, text) from public;
grant execute on function public.v177_require_json_array(jsonb, text) to anon;
grant execute on function public.v177_require_json_array(jsonb, text) to authenticated;
grant execute on function public.v177_require_json_array(jsonb, text) to service_role;
revoke all on function public.v177_require_json_object(jsonb, text) from public;
grant execute on function public.v177_require_json_object(jsonb, text) to anon;
grant execute on function public.v177_require_json_object(jsonb, text) to authenticated;
grant execute on function public.v177_require_json_object(jsonb, text) to service_role;
revoke all on function public.v177_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) from public;
grant execute on function public.v177_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) to authenticated;
grant execute on function public.v177_save_inventory_count_section(text, text, text, bigint, jsonb, text, text) to service_role;
revoke all on function public.v186_confirm_live_inventory_count(text, text, bigint, bigint, jsonb, jsonb, text) from public;
grant execute on function public.v186_confirm_live_inventory_count(text, text, bigint, bigint, jsonb, jsonb, text) to service_role;
grant execute on function public.v186_confirm_live_inventory_count(text, text, bigint, bigint, jsonb, jsonb, text) to authenticated;
revoke all on function public.v188_apply_month_end_qr_adjustment(text, text, text, text, numeric, numeric, text, text, text, text) from public;
grant execute on function public.v188_apply_month_end_qr_adjustment(text, text, text, text, numeric, numeric, text, text, text, text) to service_role;
grant execute on function public.v188_apply_month_end_qr_adjustment(text, text, text, text, numeric, numeric, text, text, text, text) to authenticated;

grant execute on function public.assert_app_state_not_rollback_v185(jsonb, jsonb, jsonb) to public;
grant execute on function public.guard_app_state_update_v185() to public;
grant execute on function public.qr_inventory_entry_operation_id(uuid, text) to public;
grant execute on function public.seika_enqueue_low_quality_push_v1144() to public;
grant execute on function public.seika_item_name_group_v1200(text) to public;
grant execute on function public.seika_qr_block_lot_hard_delete_v1119() to public;
grant execute on function public.seika_qr_guard_lot_soft_delete_v1119() to public;
grant execute on function public.seika_qr_guard_quality_invalidation_v1119() to public;
grant execute on function public.seika_qr_guard_quality_photo_invalidation_v1119() to public;
grant execute on function public.seika_quality_archive_after_photo_finalize_v1102() to public;
grant execute on function public.seika_quality_archive_before_insert_v1102() to public;
grant execute on function public.set_updated_at() to public;
grant execute on function public.v177_inventory_sessions(jsonb) to public;
grant execute on function public.v177_parse_bigint(text, text, bigint) to public;
grant execute on function public.v177_parse_boolean(text, text, boolean) to public;
grant execute on function public.v177_parse_decimal(text, text, boolean) to public;
grant execute on function public.v177_require_json_array(jsonb, text) to public;
grant execute on function public.v177_require_json_object(jsonb, text) to public;

-- ===== テーブルの権限
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_admins to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_admins to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_settings to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_settings to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_20260710 to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_20260710 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_20260721 to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_20260721 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_blobs_v1167 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_migration_audit_v1167 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backup_slots_v1167 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.app_state_backups to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory_items to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory_items to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory_movements to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory_movements to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory_records to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.inventory_records to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.items to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.items to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.notifications to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.notifications to service_role;
grant SELECT on public.profiles to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.profiles to service_role;
grant SELECT on public.purchase_prices to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.purchase_prices to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_destinations to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_destinations to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_inventory_sessions to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_inventory_sessions to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lot_delete_audit_events_v1119 to service_role;
grant SELECT on public.qr_lot_monthly_snapshots to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lot_monthly_snapshots to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, UPDATE on public.qr_lot_movements to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lot_movements to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lot_movements_backup_20260721 to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lot_movements_backup_20260721 to service_role;
grant INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lots to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lots to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lots_backup_20260721 to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_lots_backup_20260721 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_monthly_exports to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_monthly_exports to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_quality_evaluations to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_quality_photos to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_scan_logs to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_scan_logs to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_settings to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_settings to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_storage_locations to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.qr_storage_locations to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.quality_push_queue_v1144 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_admin_notice_audit_v1150 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_admin_notice_operations_v1150 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_admin_notices_v1150 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_auth_migration_log_v1200 to anon;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_auth_migration_log_v1200 to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_auth_migration_log_v1200 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_feature_modes_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_feedback_reports to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_fifo_decision_audit_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_fifo_hold_override_audit_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_fifo_lot_holds_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_fifo_mode_transition_approvals_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_fifo_operation_requests_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_inventory_counts_backup_v1205 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_item_aging_policies_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_monthly_archives to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_policy_audit_v1136 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_policy_backup_v1203 to anon;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_policy_backup_v1203 to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_policy_backup_v1203 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_qr_operation_requests_v1156 to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_rpc_test_result to anon;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_rpc_test_result to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.seika_rpc_test_result to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.stock_movements to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.stock_movements to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.trimming_job_cancel_audit_v1144 to service_role;
grant SELECT on public.trimming_job_lots to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.trimming_job_lots to service_role;
grant SELECT on public.trimming_job_outputs to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.trimming_job_outputs to service_role;
grant SELECT on public.trimming_jobs to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.trimming_jobs to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.user_admin_audit_logs to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.waste_records to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.waste_records to service_role;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.web_push_subscriptions_v1144 to service_role;
