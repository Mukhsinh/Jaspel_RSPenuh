-- ============================================================================
-- PINTAR JP (JASPEL Enterprise) — Consolidated Production Database Schema
-- Target Supabase Project: ixhuwepkftollytftfkf
-- Aligned with DOCS/DATABASE_SCHEMA.md, all migrations, and application code
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 1. MASTER DATA TABLES (m_*)
-- ============================================================================

-- 1.1 Master Units (m_units)
CREATE TABLE IF NOT EXISTS public.m_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  proportion_percentage NUMERIC(8,4) NOT NULL DEFAULT 0.0000 CHECK (proportion_percentage >= 0 AND proportion_percentage <= 100),
  proportion_umum_percentage NUMERIC(8,4) DEFAULT NULL CHECK (proportion_umum_percentage IS NULL OR (proportion_umum_percentage >= 0 AND proportion_umum_percentage <= 100)),
  use_same_proportion BOOLEAN DEFAULT true,
  remuneration_style VARCHAR(50) DEFAULT 'score_based',
  kpi_schema_mode VARCHAR(50) DEFAULT 'same',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 1.2 Master Employees (m_employees)
CREATE TABLE IF NOT EXISTS public.m_employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE, -- Linked to auth.users.id
  employee_code VARCHAR(100) UNIQUE NOT NULL,
  full_name VARCHAR(255) NOT NULL,
  unit_id UUID NOT NULL REFERENCES public.m_units(id) ON DELETE RESTRICT,
  role VARCHAR(50) NOT NULL DEFAULT 'employee' CHECK (role IN ('superadmin', 'unit_manager', 'employee')),
  email VARCHAR(255) UNIQUE,
  phone VARCHAR(50),
  nik VARCHAR(50),
  position VARCHAR(255),
  bank_name VARCHAR(100),
  bank_account_number VARCHAR(100),
  bank_account_name VARCHAR(255),
  tax_status VARCHAR(20) DEFAULT 'TK/0',
  tax_type VARCHAR(20) DEFAULT 'TER',
  employment_status VARCHAR(50),
  employee_status VARCHAR(50),
  pns_grade VARCHAR(20),
  is_contract BOOLEAN DEFAULT false,
  contract_percentage NUMERIC(5,2) DEFAULT 100,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 1.3 Master KPI Categories (m_kpi_categories)
CREATE TABLE IF NOT EXISTS public.m_kpi_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id UUID NOT NULL REFERENCES public.m_units(id) ON DELETE CASCADE,
  category VARCHAR(10) NOT NULL CHECK (category IN ('P1', 'P2', 'P3', 'P4')),
  category_name VARCHAR(255) NOT NULL,
  weight_percentage NUMERIC(5,2) NOT NULL DEFAULT 0.00 CHECK (weight_percentage >= 0 AND weight_percentage <= 100),
  description TEXT,
  configuration_style VARCHAR(50) DEFAULT 'percentage',
  is_weighted BOOLEAN DEFAULT true,
  revenue_type VARCHAR(20) DEFAULT 'bpjs',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT m_kpi_categories_unit_id_category_revenue_type_key UNIQUE (unit_id, category, revenue_type)
);

-- 1.4 Master KPI Indicators (m_kpi_indicators)
CREATE TABLE IF NOT EXISTS public.m_kpi_indicators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES public.m_kpi_categories(id) ON DELETE CASCADE,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  target_value NUMERIC(15,4) DEFAULT 100.0000,
  weight_percentage NUMERIC(5,2) NOT NULL DEFAULT 0.00 CHECK (weight_percentage >= 0 AND weight_percentage <= 100),
  measurement_unit VARCHAR(50),
  measurement_type VARCHAR(50) DEFAULT 'scoring',
  calculation_method VARCHAR(20) DEFAULT 'indexing' CHECK (calculation_method IN ('indexing', 'priority')),
  base_index_value NUMERIC(15,4) DEFAULT 0.0000,
  unit_tariff NUMERIC(15,4) DEFAULT 0.0000,
  service_types TEXT[] DEFAULT '{}'::text[],
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (category_id, code)
);

-- 1.5 Master KPI Sub Indicators (m_kpi_sub_indicators)
CREATE TABLE IF NOT EXISTS public.m_kpi_sub_indicators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  indicator_id UUID NOT NULL REFERENCES public.m_kpi_indicators(id) ON DELETE CASCADE,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  target_value NUMERIC(15,4) DEFAULT 100.0000,
  weight_percentage NUMERIC(5,2) NOT NULL DEFAULT 0.00 CHECK (weight_percentage >= 0 AND weight_percentage <= 100),
  scoring_criteria JSONB DEFAULT '[]'::jsonb,
  measurement_unit VARCHAR(50),
  measurement_type VARCHAR(50) DEFAULT 'scoring',
  unit_tariff NUMERIC(15,4) DEFAULT 0.0000,
  base_index_value NUMERIC(15,4) DEFAULT 0.0000,
  service_types TEXT[] DEFAULT '{}'::text[],
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (indicator_id, code)
);

-- 1.6 Master Tariffs (m_master_tariffs)
CREATE TABLE IF NOT EXISTS public.m_master_tariffs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  service_type VARCHAR(100),
  amount NUMERIC(18,4) NOT NULL DEFAULT 0,
  type VARCHAR(20) NOT NULL DEFAULT 'index' CHECK (type IN ('index', 'activity')),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 1.7 Master Unit Activities (m_unit_activities)
CREATE TABLE IF NOT EXISTS public.m_unit_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id UUID REFERENCES public.m_units(id) ON DELETE CASCADE,
  category_id UUID REFERENCES public.m_kpi_categories(id) ON DELETE CASCADE,
  code TEXT,
  activity_name TEXT NOT NULL,
  base_index_value NUMERIC(15,4) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. TRANSACTION TABLES (t_*)
-- ============================================================================

-- 2.1 Pool Dana (t_pool)
CREATE TABLE IF NOT EXISTS public.t_pool (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL UNIQUE, -- Format: YYYY-MM
  revenue_bpjs NUMERIC(18,2) DEFAULT 0.00,
  revenue_umum NUMERIC(18,2) DEFAULT 0.00,
  revenue_total NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  deduction_total NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  net_pool NUMERIC(18,2) GENERATED ALWAYS AS (revenue_total - deduction_total) STORED,
  allocation_percentage_bpjs NUMERIC(5,2) DEFAULT 100.00,
  allocation_percentage_umum NUMERIC(5,2) DEFAULT 100.00,
  global_allocation_percentage NUMERIC(5,2) NOT NULL DEFAULT 100.00 CHECK (global_allocation_percentage >= 0 AND global_allocation_percentage <= 100),
  allocated_bpjs NUMERIC(18,2) DEFAULT 0.00,
  allocated_umum NUMERIC(18,2) DEFAULT 0.00,
  allocated_amount NUMERIC(18,2) GENERATED ALWAYS AS ((revenue_total - deduction_total) * global_allocation_percentage / 100) STORED,
  status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'distributed')),
  approved_by UUID REFERENCES public.m_employees(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.2 Pool Revenue Details (t_pool_revenue)
CREATE TABLE IF NOT EXISTS public.t_pool_revenue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id UUID REFERENCES public.t_pool(id) ON DELETE CASCADE,
  revenue_code VARCHAR(20),
  revenue_type VARCHAR(50),
  category VARCHAR(50),
  description VARCHAR(255),
  amount NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  patient_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.3 Pool Deduction Details (t_pool_deduction)
CREATE TABLE IF NOT EXISTS public.t_pool_deduction (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id UUID REFERENCES public.t_pool(id) ON DELETE CASCADE,
  description VARCHAR(255),
  amount NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.4 KPI Assessments (t_kpi_assessments) — Core transaction table
CREATE TABLE IF NOT EXISTS public.t_kpi_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  indicator_id UUID NOT NULL REFERENCES public.m_kpi_indicators(id) ON DELETE CASCADE,
  sub_indicator_id UUID REFERENCES public.m_kpi_sub_indicators(id) ON DELETE CASCADE,
  period VARCHAR(7) NOT NULL,
  revenue_type VARCHAR(20) DEFAULT 'bpjs',
  realization_value NUMERIC(15,4) NOT NULL DEFAULT 0.0000,
  target_value NUMERIC(15,4) NOT NULL DEFAULT 0.0000,
  weight_percentage NUMERIC(5,2) NOT NULL DEFAULT 0.00,
  achievement_percentage NUMERIC(10,2),
  score NUMERIC(15,4),
  sub_assessments JSONB DEFAULT '[]'::jsonb,
  is_contract BOOLEAN DEFAULT false,
  contract_percentage NUMERIC(5,2) DEFAULT 100,
  notes TEXT,
  assessor_id UUID REFERENCES public.m_employees(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Critical Unique Indexes for t_kpi_assessments
CREATE UNIQUE INDEX IF NOT EXISTS t_kpi_assessments_unique_key
  ON public.t_kpi_assessments (employee_id, indicator_id, period, sub_indicator_id, revenue_type)
  NULLS NOT DISTINCT;

CREATE UNIQUE INDEX IF NOT EXISTS unique_assessment_main
  ON public.t_kpi_assessments (employee_id, indicator_id, period, revenue_type)
  WHERE sub_indicator_id IS NULL;

-- 2.5 KPI Realization (t_realization)
CREATE TABLE IF NOT EXISTS public.t_realization (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  indicator_id UUID REFERENCES public.m_kpi_indicators(id) ON DELETE CASCADE,
  sub_indicator_id UUID REFERENCES public.m_kpi_sub_indicators(id) ON DELETE CASCADE,
  period VARCHAR(7) NOT NULL,
  realization_value NUMERIC(15,4) NOT NULL DEFAULT 0.0000,
  achievement_percentage NUMERIC(10,2),
  score NUMERIC(15,4),
  notes TEXT,
  created_by UUID REFERENCES public.m_employees(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.6 Employee Period Locking & Snapshots
CREATE TABLE IF NOT EXISTS public.t_employee_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL UNIQUE,
  period_name VARCHAR(100) NOT NULL,
  is_locked BOOLEAN NOT NULL DEFAULT FALSE,
  locked_at TIMESTAMPTZ,
  locked_by VARCHAR(255),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.t_employee_period_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL,
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  employee_code VARCHAR(100),
  full_name VARCHAR(255) NOT NULL,
  unit_id UUID NOT NULL REFERENCES public.m_units(id) ON DELETE RESTRICT,
  position VARCHAR(255),
  role VARCHAR(50) DEFAULT 'employee',
  employee_status VARCHAR(50),
  employment_status VARCHAR(50),
  pns_grade VARCHAR(50),
  tax_status VARCHAR(50),
  tax_type VARCHAR(50),
  nik VARCHAR(100),
  bank_name VARCHAR(100),
  bank_account_number VARCHAR(100),
  bank_account_name VARCHAR(255),
  phone VARCHAR(100),
  email VARCHAR(255),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_contract BOOLEAN DEFAULT FALSE,
  contract_percentage NUMERIC(5,2) DEFAULT 100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_period_employee UNIQUE (period, employee_id)
);

-- 2.7 Unit Period Locking & Snapshots
CREATE TABLE IF NOT EXISTS public.t_unit_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL UNIQUE,
  period_name VARCHAR(100) NOT NULL,
  is_locked BOOLEAN NOT NULL DEFAULT FALSE,
  locked_at TIMESTAMPTZ,
  locked_by VARCHAR(255),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.t_unit_period_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL,
  unit_id UUID NOT NULL REFERENCES public.m_units(id) ON DELETE CASCADE,
  code VARCHAR(50),
  name VARCHAR(255),
  proportion_percentage NUMERIC(8,4) NOT NULL DEFAULT 0,
  proportion_umum_percentage NUMERIC(8,4) DEFAULT 0,
  use_same_proportion BOOLEAN DEFAULT TRUE,
  remuneration_style VARCHAR(50) DEFAULT 'score_based',
  kpi_schema_mode VARCHAR(50) DEFAULT 'different',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_unit_period_snapshots UNIQUE (period, unit_id)
);

-- 2.8 Calculation & Score Tables
CREATE TABLE IF NOT EXISTS public.t_unit_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id UUID NOT NULL REFERENCES public.m_units(id) ON DELETE CASCADE,
  period VARCHAR(7) NOT NULL,
  total_score NUMERIC(15,4) NOT NULL DEFAULT 0.0000,
  unit_weight_percentage NUMERIC(5,2) NOT NULL DEFAULT 0.00,
  weighted_score NUMERIC(15,4) NOT NULL DEFAULT 0.0000,
  unit_allocated_amount NUMERIC(18,2) DEFAULT 0.00,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (unit_id, period)
);

CREATE TABLE IF NOT EXISTS public.t_individual_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  period VARCHAR(7) NOT NULL,
  p1_score NUMERIC(15,4) DEFAULT 0.0000,
  p2_score NUMERIC(15,4) DEFAULT 0.0000,
  p3_score NUMERIC(15,4) DEFAULT 0.0000,
  p1_weighted NUMERIC(15,4) DEFAULT 0.0000,
  p2_weighted NUMERIC(15,4) DEFAULT 0.0000,
  p3_weighted NUMERIC(15,4) DEFAULT 0.0000,
  individual_total_score NUMERIC(15,4) DEFAULT 0.0000,
  individual_weight_percentage NUMERIC(5,2) NOT NULL DEFAULT 100.00,
  weighted_individual_score NUMERIC(15,4) DEFAULT 0.0000,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (employee_id, period)
);

CREATE TABLE IF NOT EXISTS public.t_calculation_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  period VARCHAR(7) NOT NULL,
  pool_id UUID NOT NULL REFERENCES public.t_pool(id) ON DELETE CASCADE,
  unit_score NUMERIC(15,4) DEFAULT 0.0000,
  individual_score NUMERIC(15,4) DEFAULT 0.0000,
  final_score NUMERIC(15,4) DEFAULT 0.0000,
  unit_allocated_amount NUMERIC(18,2) DEFAULT 0.00,
  score_proportion NUMERIC(10,6) DEFAULT 0.000000,
  gross_incentive NUMERIC(18,2) DEFAULT 0.00,
  tax_amount NUMERIC(18,2) DEFAULT 0.00,
  net_incentive NUMERIC(18,2) DEFAULT 0.00,
  calculation_metadata JSONB,
  calculated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (employee_id, period)
);

CREATE TABLE IF NOT EXISTS public.t_calculation_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL,
  status VARCHAR(20) NOT NULL CHECK (status IN ('success', 'error')),
  employee_count INTEGER DEFAULT 0,
  error_message TEXT,
  error_details JSONB,
  started_at TIMESTAMPTZ NOT NULL,
  completed_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.t_history_pir (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period VARCHAR(7) NOT NULL,
  unit_id UUID NOT NULL REFERENCES public.m_units(id) ON DELETE CASCADE,
  unit_name VARCHAR(255),
  net_pool_amount NUMERIC(18,2),
  proportion_percentage NUMERIC(8,4),
  allocated_for_unit NUMERIC(18,2),
  total_skor_kolektif NUMERIC(18,4),
  pir_value NUMERIC(18,6),
  employee_count INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 3. DOCTOR REMUNERATION TABLES (remunerasi_*)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.remunerasi_periode (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  periode VARCHAR(7) NOT NULL UNIQUE,
  total_pagu NUMERIC(18,2) NOT NULL DEFAULT 0,
  status VARCHAR(20) DEFAULT 'draft',
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.remunerasi_kategori (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kode_layanan VARCHAR(50) UNIQUE NOT NULL,
  nama_layanan VARCHAR(255) NOT NULL,
  kategori VARCHAR(100) NOT NULL,
  sub_kategori VARCHAR(100),
  nilai_indeks_dasar NUMERIC(10,4) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.remunerasi_transaksi_dokter (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  periode_id UUID NOT NULL REFERENCES public.remunerasi_periode(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  kode_layanan VARCHAR(50) NOT NULL REFERENCES public.remunerasi_kategori(kode_layanan),
  qty NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.remunerasi_master_dokter (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  periode_id UUID NOT NULL REFERENCES public.remunerasi_periode(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  remun_kategori_id UUID REFERENCES public.remunerasi_kategori(id) ON DELETE SET NULL,
  index_id UUID,
  pagu_guarantee_fee NUMERIC(18,2) NOT NULL DEFAULT 0,
  persentase_pajak NUMERIC(5,2) NOT NULL DEFAULT 0,
  no_rekening VARCHAR(50),
  bank_tujuan VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (periode_id, employee_id)
);

CREATE TABLE IF NOT EXISTS public.remunerasi_hasil (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  periode_id UUID NOT NULL REFERENCES public.remunerasi_periode(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  total_langsung NUMERIC(18,2) NOT NULL DEFAULT 0,
  total_poin_indeks NUMERIC(18,4) NOT NULL DEFAULT 0,
  konversi_indeks_rupiah NUMERIC(18,2) NOT NULL DEFAULT 0,
  bruto NUMERIC(18,2) NOT NULL DEFAULT 0,
  pajak_nominal NUMERIC(18,2) NOT NULL DEFAULT 0,
  netto NUMERIC(18,2) NOT NULL DEFAULT 0,
  pir_apply NUMERIC(18,6) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (periode_id, employee_id)
);

-- ============================================================================
-- 4. SYSTEM TABLES (Settings, Notifications, Audit & Auth Logs)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.t_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  description TEXT,
  created_by UUID,
  updated_by UUID,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.t_notification (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.m_employees(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT DEFAULT 'general',
  read BOOLEAN DEFAULT false,
  link TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.t_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id UUID, -- References auth.users.id
  user_name TEXT,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('CREATE', 'UPDATE', 'DELETE', 'LOGIN', 'LOGOUT', 'ACCESS')),
  record_id TEXT,
  ip_address TEXT,
  old_value JSONB,
  new_value JSONB,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.t_auth_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID, -- References auth.users.id
  action TEXT NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  success BOOLEAN DEFAULT true,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 5. PERFORMANCE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_units_active ON public.m_units(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_employees_unit ON public.m_employees(unit_id);
CREATE INDEX IF NOT EXISTS idx_employees_role ON public.m_employees(role);
CREATE INDEX IF NOT EXISTS idx_employees_active_unit ON public.m_employees(is_active, unit_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_kpi_categories_unit ON public.m_kpi_categories(unit_id);
CREATE INDEX IF NOT EXISTS idx_kpi_categories_revenue_type ON public.m_kpi_categories(revenue_type);
CREATE INDEX IF NOT EXISTS idx_kpi_indicators_category ON public.m_kpi_indicators(category_id);
CREATE INDEX IF NOT EXISTS idx_kpi_indicators_active ON public.m_kpi_indicators(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_kpi_sub_indicators_indicator ON public.m_kpi_sub_indicators(indicator_id);
CREATE INDEX IF NOT EXISTS idx_kpi_assessments_period_rev ON public.t_kpi_assessments(period, revenue_type);
CREATE INDEX IF NOT EXISTS idx_kpi_assessments_emp_period ON public.t_kpi_assessments(employee_id, period);
CREATE INDEX IF NOT EXISTS idx_kpi_assessments_indicator ON public.t_kpi_assessments(indicator_id);
CREATE INDEX IF NOT EXISTS idx_realization_employee ON public.t_realization(employee_id);
CREATE INDEX IF NOT EXISTS idx_realization_period ON public.t_realization(period);
CREATE INDEX IF NOT EXISTS idx_pool_period ON public.t_pool(period);
CREATE INDEX IF NOT EXISTS idx_calculation_period ON public.t_calculation_results(period);
CREATE INDEX IF NOT EXISTS idx_calculation_employee ON public.t_calculation_results(employee_id);
CREATE INDEX IF NOT EXISTS idx_calculation_log_period ON public.t_calculation_log(period);
CREATE INDEX IF NOT EXISTS idx_calculation_log_status ON public.t_calculation_log(status);
CREATE INDEX IF NOT EXISTS idx_emp_snap_period ON public.t_employee_period_snapshots(period);
CREATE INDEX IF NOT EXISTS idx_emp_snap_period_unit ON public.t_employee_period_snapshots(period, unit_id);
CREATE INDEX IF NOT EXISTS idx_emp_snap_period_emp ON public.t_employee_period_snapshots(period, employee_id);
CREATE INDEX IF NOT EXISTS idx_emp_snap_period_active ON public.t_employee_period_snapshots(period, is_active);
CREATE INDEX IF NOT EXISTS idx_unit_snap_period ON public.t_unit_period_snapshots(period);
CREATE INDEX IF NOT EXISTS idx_unit_snap_period_unit ON public.t_unit_period_snapshots(period, unit_id);
CREATE INDEX IF NOT EXISTS idx_rem_trans_periode ON public.remunerasi_transaksi_dokter(periode_id);
CREATE INDEX IF NOT EXISTS idx_rem_trans_employee ON public.remunerasi_transaksi_dokter(employee_id);
CREATE INDEX IF NOT EXISTS idx_rem_hasil_periode ON public.remunerasi_hasil(periode_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.t_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_table ON public.t_audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_notification_user ON public.t_notification(user_id, read);

-- ============================================================================
-- 6. HELPER FUNCTIONS & TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.is_superadmin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN (
    COALESCE((auth.jwt() -> 'user_metadata' ->> 'role') = 'superadmin', false)
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'superadmin', false)
    OR EXISTS (
      SELECT 1 FROM public.m_employees
      WHERE (user_id = auth.uid() OR email = auth.jwt() ->> 'email')
        AND role = 'superadmin'
        AND is_active = true
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_unit_manager()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN (
    COALESCE((auth.jwt() -> 'user_metadata' ->> 'role') = 'unit_manager', false)
    OR COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'unit_manager', false)
    OR EXISTS (
      SELECT 1 FROM public.m_employees
      WHERE (user_id = auth.uid() OR email = auth.jwt() ->> 'email')
        AND role = 'unit_manager'
        AND is_active = true
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_user_unit_id()
RETURNS UUID AS $$
BEGIN
  RETURN (
    SELECT unit_id FROM public.m_employees
    WHERE user_id = auth.uid() OR email = auth.jwt() ->> 'email'
    LIMIT 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.log_audit_event(
  p_table_name TEXT,
  p_operation TEXT,
  p_record_id TEXT DEFAULT NULL,
  p_old_value JSONB DEFAULT NULL,
  p_new_value JSONB DEFAULT NULL,
  p_details TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_audit_id UUID;
  v_user_id UUID;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  v_user_name := COALESCE(
    auth.jwt() -> 'user_metadata' ->> 'full_name',
    auth.jwt() ->> 'email'
  );
  INSERT INTO public.t_audit_log (
    user_id, user_name, table_name, operation, record_id, old_value, new_value, details
  ) VALUES (
    v_user_id, v_user_name, p_table_name, p_operation, p_record_id, p_old_value, p_new_value, p_details
  )
  RETURNING id INTO v_audit_id;
  RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.log_auth_event(
  p_action TEXT,
  p_success BOOLEAN DEFAULT true,
  p_error_message TEXT DEFAULT NULL,
  p_ip_address TEXT DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_log_id UUID;
BEGIN
  INSERT INTO public.t_auth_log (
    user_id, action, success, error_message, ip_address, user_agent
  ) VALUES (
    auth.uid(), p_action, p_success, p_error_message, p_ip_address, p_user_agent
  )
  RETURNING id INTO v_log_id;
  RETURN v_log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dashboard RPC Functions
CREATE OR REPLACE FUNCTION public.get_dashboard_stats_optimized()
RETURNS TABLE (
  total_employees BIGINT,
  total_units BIGINT,
  avg_score NUMERIC,
  completion_rate NUMERIC,
  employee_trend NUMERIC,
  score_trend NUMERIC,
  completion_trend NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_month_start TIMESTAMPTZ := date_trunc('month', NOW());
BEGIN
  RETURN QUERY
  WITH current_stats AS (
    SELECT
      (SELECT COUNT(*) FROM public.m_employees WHERE is_active = true AND role != 'superadmin') AS total_employees,
      (SELECT COUNT(*) FROM public.m_units WHERE is_active = true) AS total_units,
      (SELECT COALESCE(AVG(score), 0) FROM public.t_kpi_assessments WHERE period = to_char(NOW(), 'YYYY-MM')) AS avg_score,
      (SELECT
         CASE WHEN COUNT(DISTINCT e.id) > 0 THEN
           (COUNT(DISTINCT a.employee_id)::NUMERIC / COUNT(DISTINCT e.id)::NUMERIC) * 100
         ELSE 0 END
       FROM public.m_employees e
       LEFT JOIN public.t_kpi_assessments a ON e.id = a.employee_id AND a.period = to_char(NOW(), 'YYYY-MM')
       WHERE e.is_active = true AND e.role != 'superadmin'
      ) AS completion_rate
  ),
  prev_stats AS (
    SELECT
      (SELECT COALESCE(AVG(score), 0) FROM public.t_kpi_assessments WHERE period = to_char(NOW() - interval '1 month', 'YYYY-MM')) AS prev_avg_score,
      (SELECT COUNT(*) FROM public.m_employees WHERE is_active = true AND role != 'superadmin' AND created_at < current_month_start) AS prev_total_employees
  )
  SELECT
    cs.total_employees,
    cs.total_units,
    cs.avg_score,
    cs.completion_rate,
    CASE WHEN ps.prev_total_employees > 0 THEN ((cs.total_employees - ps.prev_total_employees)::NUMERIC / ps.prev_total_employees::NUMERIC) * 100 ELSE 0 END AS employee_trend,
    CASE WHEN ps.prev_avg_score > 0 THEN ((cs.avg_score - ps.prev_avg_score) / ps.prev_avg_score) * 100 ELSE 0 END AS score_trend,
    0::NUMERIC AS completion_trend
  FROM current_stats cs, prev_stats ps;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_dashboard_aggregated_stats(
  target_year INTEGER DEFAULT EXTRACT(YEAR FROM NOW())::INTEGER,
  target_month INTEGER DEFAULT EXTRACT(MONTH FROM NOW())::INTEGER
)
RETURNS TABLE (
  total_units BIGINT,
  total_employees BIGINT,
  avg_score NUMERIC,
  completion_rate NUMERIC,
  active_pools BIGINT,
  total_pool_amount NUMERIC,
  total_indicators BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  target_period TEXT := lpad(target_year::TEXT, 4, '0') || '-' || lpad(target_month::TEXT, 2, '0');
BEGIN
  RETURN QUERY
  WITH stats AS (
    SELECT
      (SELECT COUNT(*) FROM public.m_units WHERE is_active = true) AS unit_count,
      (SELECT COUNT(*) FROM public.m_employees WHERE is_active = true AND role != 'superadmin') AS employee_count,
      (SELECT COALESCE(AVG(score), 0) FROM public.t_kpi_assessments WHERE period = target_period) AS avg_total_score,
      (SELECT COUNT(DISTINCT employee_id) FROM public.t_kpi_assessments WHERE period = target_period) AS assessed_count,
      (SELECT COUNT(*) FROM public.t_pool WHERE period = target_period) AS pool_count,
      (SELECT COALESCE(SUM(allocated_amount), 0) FROM public.t_pool WHERE period = target_period) AS pool_amount,
      (SELECT COUNT(*) FROM public.m_kpi_indicators WHERE is_active = true) AS indicator_count
  )
  SELECT
    s.unit_count,
    s.employee_count,
    s.avg_total_score,
    CASE WHEN s.employee_count > 0 THEN (s.assessed_count::NUMERIC / s.employee_count::NUMERIC) * 100 ELSE 0 END AS completion_rate,
    s.pool_count,
    s.pool_amount,
    s.indicator_count
  FROM stats s;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_top_performers(performer_limit INTEGER DEFAULT 5)
RETURNS TABLE (
  employee_id UUID,
  employee_name TEXT,
  unit_name TEXT,
  avg_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id AS employee_id,
    e.full_name::TEXT AS employee_name,
    u.name::TEXT AS unit_name,
    AVG(a.score) AS avg_score
  FROM public.m_employees e
  INNER JOIN public.m_units u ON u.id = e.unit_id
  INNER JOIN public.t_kpi_assessments a ON a.employee_id = e.id
  WHERE e.is_active = true AND u.is_active = true
    AND a.period = to_char(NOW(), 'YYYY-MM')
  GROUP BY e.id, e.full_name, u.name
  ORDER BY AVG(a.score) DESC
  LIMIT performer_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unit_performance_stats()
RETURNS TABLE (
  unit_id UUID,
  unit_name TEXT,
  employee_count BIGINT,
  avg_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    u.id AS unit_id,
    u.name::TEXT AS unit_name,
    COUNT(DISTINCT e.id) AS employee_count,
    COALESCE(AVG(a.score), 0) AS avg_score
  FROM public.m_units u
  LEFT JOIN public.m_employees e ON e.unit_id = u.id AND e.is_active = true
  LEFT JOIN public.t_kpi_assessments a ON a.employee_id = e.id AND a.period = to_char(NOW(), 'YYYY-MM')
  WHERE u.is_active = true
  GROUP BY u.id, u.name
  ORDER BY u.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_dashboard_stats_optimized() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dashboard_aggregated_stats(INTEGER, INTEGER) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_top_performers(INTEGER) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_performance_stats() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.log_audit_event(TEXT, TEXT, TEXT, JSONB, JSONB, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.log_auth_event(TEXT, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- Updated_at Triggers
DROP TRIGGER IF EXISTS trg_units_updated_at ON public.m_units;
CREATE TRIGGER trg_units_updated_at BEFORE UPDATE ON public.m_units FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_employees_updated_at ON public.m_employees;
CREATE TRIGGER trg_employees_updated_at BEFORE UPDATE ON public.m_employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_categories_updated_at ON public.m_kpi_categories;
CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON public.m_kpi_categories FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_indicators_updated_at ON public.m_kpi_indicators;
CREATE TRIGGER trg_indicators_updated_at BEFORE UPDATE ON public.m_kpi_indicators FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_sub_indicators_updated_at ON public.m_kpi_sub_indicators;
CREATE TRIGGER trg_sub_indicators_updated_at BEFORE UPDATE ON public.m_kpi_sub_indicators FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_assessments_updated_at ON public.t_kpi_assessments;
CREATE TRIGGER trg_assessments_updated_at BEFORE UPDATE ON public.t_kpi_assessments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_settings_updated_at ON public.t_settings;
CREATE TRIGGER trg_settings_updated_at BEFORE UPDATE ON public.t_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_master_tariffs_updated_at ON public.m_master_tariffs;
CREATE TRIGGER trg_master_tariffs_updated_at BEFORE UPDATE ON public.m_master_tariffs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- 7. VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW public.v_assessment_status AS
SELECT
  e.id AS employee_id,
  e.full_name,
  e.role,
  e.unit_id,
  u.name AS unit_name,
  p.period,
  COUNT(DISTINCT i.id) AS total_indicators,
  COUNT(DISTINCT CASE WHEN a.id IS NOT NULL THEN i.id END) AS assessed_indicators,
  CASE
    WHEN COUNT(DISTINCT a.indicator_id) = 0 THEN 'Belum Dinilai'
    WHEN COUNT(DISTINCT a.indicator_id) >= COUNT(DISTINCT i.id) THEN 'Selesai'
    ELSE 'Sebagian'
  END AS status,
  ROUND(
    (COUNT(DISTINCT a.indicator_id)::DECIMAL / NULLIF(COUNT(DISTINCT i.id), 0) * 100),
    2
  ) AS completion_percentage
FROM public.m_employees e
JOIN public.m_units u ON e.unit_id = u.id
CROSS JOIN (
  SELECT DISTINCT period
  FROM public.t_pool
  ORDER BY period DESC
  LIMIT 12
) p
LEFT JOIN public.m_kpi_categories c ON c.unit_id = e.unit_id AND c.is_active = true
LEFT JOIN public.m_kpi_indicators i ON i.category_id = c.id AND i.is_active = true
LEFT JOIN public.t_kpi_assessments a ON a.employee_id = e.id
  AND a.indicator_id = i.id
  AND a.period = p.period
  AND a.sub_indicator_id IS NULL
WHERE e.is_active = true AND e.role != 'superadmin'
GROUP BY e.id, e.full_name, e.role, e.unit_id, u.name, p.period
ORDER BY e.full_name, p.period DESC;

CREATE OR REPLACE VIEW public.v_audit_log_with_user AS
SELECT
  al.*,
  COALESCE(
    (SELECT full_name FROM public.m_employees WHERE user_id = al.user_id LIMIT 1),
    al.user_name
  ) AS employee_name,
  (SELECT email FROM auth.users WHERE id = al.user_id LIMIT 1) AS user_email
FROM public.t_audit_log al;

CREATE OR REPLACE VIEW public.v_auth_log_with_user AS
SELECT
  al.*,
  (SELECT full_name FROM public.m_employees WHERE user_id = al.user_id LIMIT 1) AS employee_name,
  (SELECT email FROM auth.users WHERE id = al.user_id LIMIT 1) AS user_email
FROM public.t_auth_log al;

GRANT SELECT ON public.v_assessment_status TO authenticated, anon, service_role;
GRANT SELECT ON public.v_audit_log_with_user TO authenticated, service_role;
GRANT SELECT ON public.v_auth_log_with_user TO authenticated, service_role;

-- ============================================================================
-- 8. ROW LEVEL SECURITY (RLS) & GRANTS
-- ============================================================================

ALTER TABLE public.m_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_kpi_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_kpi_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_kpi_sub_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_master_tariffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_unit_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_pool_revenue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_pool_deduction ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_kpi_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_realization ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_employee_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_employee_period_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_unit_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_unit_period_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_unit_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_individual_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_calculation_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_calculation_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_history_pir ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remunerasi_periode ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remunerasi_kategori ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remunerasi_transaksi_dokter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remunerasi_master_dokter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remunerasi_hasil ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_auth_log ENABLE ROW LEVEL SECURITY;

-- Grant base schema privileges
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT SELECT ON public.m_units, public.t_settings TO anon;

-- m_units policies
DROP POLICY IF EXISTS "Superadmin full access on units" ON public.m_units;
CREATE POLICY "Superadmin full access on units" ON public.m_units FOR ALL USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Everyone can view active units" ON public.m_units;
CREATE POLICY "Everyone can view active units" ON public.m_units FOR SELECT USING (is_active = true);

-- m_employees policies
DROP POLICY IF EXISTS "Superadmin full access on employees" ON public.m_employees;
CREATE POLICY "Superadmin full access on employees" ON public.m_employees FOR ALL USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Managers can view same unit" ON public.m_employees;
CREATE POLICY "Managers can view same unit" ON public.m_employees FOR SELECT USING (public.is_unit_manager() AND unit_id = public.get_user_unit_id());
DROP POLICY IF EXISTS "Employees can view self" ON public.m_employees;
CREATE POLICY "Employees can view self" ON public.m_employees FOR SELECT USING (user_id = auth.uid() OR email = auth.jwt() ->> 'email');

-- m_kpi_categories policies
DROP POLICY IF EXISTS "Superadmin full access on categories" ON public.m_kpi_categories;
CREATE POLICY "Superadmin full access on categories" ON public.m_kpi_categories FOR ALL USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Users can view categories" ON public.m_kpi_categories;
CREATE POLICY "Users can view categories" ON public.m_kpi_categories FOR SELECT USING (true);

-- m_kpi_indicators policies
DROP POLICY IF EXISTS "Superadmin full access on indicators" ON public.m_kpi_indicators;
CREATE POLICY "Superadmin full access on indicators" ON public.m_kpi_indicators FOR ALL USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Users can view indicators" ON public.m_kpi_indicators;
CREATE POLICY "Users can view indicators" ON public.m_kpi_indicators FOR SELECT USING (true);
DROP POLICY IF EXISTS "Unit manager manage indicators" ON public.m_kpi_indicators;
CREATE POLICY "Unit manager manage indicators" ON public.m_kpi_indicators FOR ALL TO authenticated
  USING (
    category_id IN (
      SELECT c.id FROM public.m_kpi_categories c
      INNER JOIN public.m_employees e ON c.unit_id = e.unit_id
      WHERE e.user_id = auth.uid() AND e.role = 'unit_manager' AND e.is_active = true
    )
  )
  WITH CHECK (
    category_id IN (
      SELECT c.id FROM public.m_kpi_categories c
      INNER JOIN public.m_employees e ON c.unit_id = e.unit_id
      WHERE e.user_id = auth.uid() AND e.role = 'unit_manager' AND e.is_active = true
    )
  );

-- m_kpi_sub_indicators policies
DROP POLICY IF EXISTS "Superadmin full access on sub indicators" ON public.m_kpi_sub_indicators;
CREATE POLICY "Superadmin full access on sub indicators" ON public.m_kpi_sub_indicators FOR ALL USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Users can view sub indicators" ON public.m_kpi_sub_indicators;
CREATE POLICY "Users can view sub indicators" ON public.m_kpi_sub_indicators FOR SELECT USING (true);
DROP POLICY IF EXISTS "Unit manager manage sub indicators" ON public.m_kpi_sub_indicators;
CREATE POLICY "Unit manager manage sub indicators" ON public.m_kpi_sub_indicators FOR ALL TO authenticated
  USING (
    indicator_id IN (
      SELECT i.id FROM public.m_kpi_indicators i
      JOIN public.m_kpi_categories c ON c.id = i.category_id
      JOIN public.m_employees e ON e.unit_id = c.unit_id
      WHERE e.user_id = auth.uid() AND e.role = 'unit_manager' AND e.is_active = true
    )
  )
  WITH CHECK (
    indicator_id IN (
      SELECT i.id FROM public.m_kpi_indicators i
      JOIN public.m_kpi_categories c ON c.id = i.category_id
      JOIN public.m_employees e ON e.unit_id = c.unit_id
      WHERE e.user_id = auth.uid() AND e.role = 'unit_manager' AND e.is_active = true
    )
  );

-- m_master_tariffs & m_unit_activities policies
DROP POLICY IF EXISTS "Authenticated manage master tariffs" ON public.m_master_tariffs;
CREATE POLICY "Authenticated manage master tariffs" ON public.m_master_tariffs FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage unit activities" ON public.m_unit_activities;
CREATE POLICY "Authenticated manage unit activities" ON public.m_unit_activities FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- t_pool, t_pool_revenue, t_pool_deduction policies
DROP POLICY IF EXISTS "Allow all for authenticated on t_pool" ON public.t_pool;
CREATE POLICY "Allow all for authenticated on t_pool" ON public.t_pool FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow all for authenticated on t_pool_revenue" ON public.t_pool_revenue;
CREATE POLICY "Allow all for authenticated on t_pool_revenue" ON public.t_pool_revenue FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow all for authenticated on t_pool_deduction" ON public.t_pool_deduction;
CREATE POLICY "Allow all for authenticated on t_pool_deduction" ON public.t_pool_deduction FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- t_kpi_assessments policies
DROP POLICY IF EXISTS "Superadmin full access on assessments" ON public.t_kpi_assessments;
CREATE POLICY "Superadmin full access on assessments" ON public.t_kpi_assessments FOR ALL USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Managers can manage unit assessments" ON public.t_kpi_assessments;
CREATE POLICY "Managers can manage unit assessments" ON public.t_kpi_assessments FOR ALL
  USING (public.is_unit_manager() AND EXISTS (SELECT 1 FROM public.m_employees WHERE id = t_kpi_assessments.employee_id AND unit_id = public.get_user_unit_id()))
  WITH CHECK (public.is_unit_manager() AND EXISTS (SELECT 1 FROM public.m_employees WHERE id = t_kpi_assessments.employee_id AND unit_id = public.get_user_unit_id()));
DROP POLICY IF EXISTS "Employees can view own assessments" ON public.t_kpi_assessments;
CREATE POLICY "Employees can view own assessments" ON public.t_kpi_assessments FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.m_employees WHERE id = t_kpi_assessments.employee_id AND user_id = auth.uid()));

-- t_realization policies
DROP POLICY IF EXISTS "Authenticated manage realization" ON public.t_realization;
CREATE POLICY "Authenticated manage realization" ON public.t_realization FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Period Locking & Snapshot policies
DROP POLICY IF EXISTS "Allow read t_employee_periods" ON public.t_employee_periods;
CREATE POLICY "Allow read t_employee_periods" ON public.t_employee_periods FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow all t_employee_periods for authenticated" ON public.t_employee_periods;
CREATE POLICY "Allow all t_employee_periods for authenticated" ON public.t_employee_periods FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow read t_employee_period_snapshots" ON public.t_employee_period_snapshots;
CREATE POLICY "Allow read t_employee_period_snapshots" ON public.t_employee_period_snapshots FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow all t_employee_period_snapshots for authenticated" ON public.t_employee_period_snapshots;
CREATE POLICY "Allow all t_employee_period_snapshots for authenticated" ON public.t_employee_period_snapshots FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow read t_unit_periods" ON public.t_unit_periods;
CREATE POLICY "Allow read t_unit_periods" ON public.t_unit_periods FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow all t_unit_periods for authenticated" ON public.t_unit_periods;
CREATE POLICY "Allow all t_unit_periods for authenticated" ON public.t_unit_periods FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow read t_unit_period_snapshots" ON public.t_unit_period_snapshots;
CREATE POLICY "Allow read t_unit_period_snapshots" ON public.t_unit_period_snapshots FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow all t_unit_period_snapshots for authenticated" ON public.t_unit_period_snapshots;
CREATE POLICY "Allow all t_unit_period_snapshots for authenticated" ON public.t_unit_period_snapshots FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Score, Calculation, and PIR policies
DROP POLICY IF EXISTS "Authenticated manage unit scores" ON public.t_unit_scores;
CREATE POLICY "Authenticated manage unit scores" ON public.t_unit_scores FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage individual scores" ON public.t_individual_scores;
CREATE POLICY "Authenticated manage individual scores" ON public.t_individual_scores FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage calculation results" ON public.t_calculation_results;
CREATE POLICY "Authenticated manage calculation results" ON public.t_calculation_results FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Superadmin full access to calculation logs" ON public.t_calculation_log;
CREATE POLICY "Superadmin full access to calculation logs" ON public.t_calculation_log FOR ALL TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());
DROP POLICY IF EXISTS "Authenticated manage history pir" ON public.t_history_pir;
CREATE POLICY "Authenticated manage history pir" ON public.t_history_pir FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Doctor Remuneration policies
DROP POLICY IF EXISTS "Authenticated manage rem_periode" ON public.remunerasi_periode;
CREATE POLICY "Authenticated manage rem_periode" ON public.remunerasi_periode FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage rem_kategori" ON public.remunerasi_kategori;
CREATE POLICY "Authenticated manage rem_kategori" ON public.remunerasi_kategori FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage rem_trans" ON public.remunerasi_transaksi_dokter;
CREATE POLICY "Authenticated manage rem_trans" ON public.remunerasi_transaksi_dokter FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage rem_master" ON public.remunerasi_master_dokter;
CREATE POLICY "Authenticated manage rem_master" ON public.remunerasi_master_dokter FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated manage rem_hasil" ON public.remunerasi_hasil;
CREATE POLICY "Authenticated manage rem_hasil" ON public.remunerasi_hasil FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Settings, Notifications, Audit & Auth Logs policies
DROP POLICY IF EXISTS "Public read settings" ON public.t_settings;
CREATE POLICY "Public read settings" ON public.t_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Superadmin manage settings" ON public.t_settings;
CREATE POLICY "Superadmin manage settings" ON public.t_settings FOR ALL TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

DROP POLICY IF EXISTS "Users manage own notifications" ON public.t_notification;
CREATE POLICY "Users manage own notifications" ON public.t_notification FOR ALL TO authenticated
  USING (
    public.is_superadmin()
    OR EXISTS (SELECT 1 FROM public.m_employees WHERE id = t_notification.user_id AND user_id = auth.uid())
  )
  WITH CHECK (true);

DROP POLICY IF EXISTS "Superadmin view audit log" ON public.t_audit_log;
CREATE POLICY "Superadmin view audit log" ON public.t_audit_log FOR SELECT TO authenticated USING (public.is_superadmin());
DROP POLICY IF EXISTS "Authenticated insert audit log" ON public.t_audit_log;
CREATE POLICY "Authenticated insert audit log" ON public.t_audit_log FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Superadmin view auth log" ON public.t_auth_log;
CREATE POLICY "Superadmin view auth log" ON public.t_auth_log FOR SELECT TO authenticated USING (public.is_superadmin());
DROP POLICY IF EXISTS "Authenticated insert auth log" ON public.t_auth_log;
CREATE POLICY "Authenticated insert auth log" ON public.t_auth_log FOR INSERT TO authenticated WITH CHECK (true);

-- ============================================================================
-- 9. DEFAULT SETTINGS SEED & STORAGE BUCKET (logos)
-- ============================================================================

INSERT INTO public.t_settings (key, value, description) VALUES
  ('company_info', '{"appName":"PINTAR JP","name":"JASPEL Enterprise","address":"","logo":"","footer":"© 2026 PINTAR JP - All Rights Reserved"}'::jsonb, 'Informasi aplikasi dan instansi'),
  ('footer', '{"text":"© 2026 PINTAR JP - All Rights Reserved"}'::jsonb, 'Teks footer aplikasi'),
  ('tax_config', '{"mechanism":"ter"}'::jsonb, 'Mekanisme perhitungan pajak (ter / final_pp80 / none)'),
  ('tax_rates', '{"TK/0":0,"TK/1":0,"TK/2":0,"TK/3":0,"K/0":0,"K/1":0,"K/2":0,"K/3":0}'::jsonb, 'Tarif pajak default per status PTKP'),
  ('calculation_params', '{"minScore":0,"maxScore":100}'::jsonb, 'Parameter kalkulasi KPI'),
  ('session_timeout', '{"hours":8}'::jsonb, 'Durasi timeout sesi login (jam)')
ON CONFLICT (key) DO NOTHING;

-- Storage bucket for company logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('logos', 'logos', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public read logos" ON storage.objects;
CREATE POLICY "Public read logos" ON storage.objects FOR SELECT USING (bucket_id = 'logos');

DROP POLICY IF EXISTS "Authenticated upload logos" ON storage.objects;
CREATE POLICY "Authenticated upload logos" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'logos');

DROP POLICY IF EXISTS "Authenticated update logos" ON storage.objects;
CREATE POLICY "Authenticated update logos" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'logos');

DROP POLICY IF EXISTS "Authenticated delete logos" ON storage.objects;
CREATE POLICY "Authenticated delete logos" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'logos');

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

