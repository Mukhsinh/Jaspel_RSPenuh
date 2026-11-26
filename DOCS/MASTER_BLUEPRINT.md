# PINTAR JP (JASPEL Enterprise) — Master Blueprint & Replication Guide

Dokumen ini adalah **Master Blueprint** resmi aplikasi **PINTAR JP (Sistem Manajemen Insentif & KPI Berbasis P1, P2, P3)**. Dirancang agar aplikasi dapat di-copy, di-clone, atau dibangun ulang dengan hasil yang **100% identik** dari sisi arsitektur, database, alur kerja, tampilan (UI/UX), optimasi egress, hingga seluruh rumus kalkulasi finansial & pajak.

---

## Indeks Dokumentasi Lengkap

| Dokumen | Cakupan |
| :--- | :--- |
| **[MASTER_BLUEPRINT.md](./MASTER_BLUEPRINT.md)** *(dokumen ini)* | Arsitektur, Tech Stack, RBAC, Keamanan & Sesi, Optimasi Egress, Daftar Route & API, Panduan Replikasi & Deployment |
| **[DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)** | Skema lengkap 20 tabel produksi, relasi, unique index kritis, mekanisme Period Locking & Snapshot |
| **[FORMULAS_AND_CALCULATION.md](./FORMULAS_AND_CALCULATION.md)** | Seluruh rumus kalkulasi 100% eksak (P1/P2/P3, Medis vs Non-Medis, Sub-Indikator, Prioritas, Potongan, Kontrak/Parsial, PIR, Rekonsiliasi Alokasi, PPh 21 TER & PP 80/2010) |
| **[WORKFLOW_AND_UI_GUIDE.md](./WORKFLOW_AND_UI_GUIDE.md)** | Alur operasional bulanan (Mermaid), Design System (`globals.css`, font, warna, layout), spesifikasi tampilan setiap halaman & ekspor |

---

## 1. Identitas & Tech Stack Aplikasi

- **Nama Paket**: `jaspel-kpi-system` v1.0.0 (Brand default: `PINTAR JP` / `JASPEL Enterprise`)
- **Framework**: Next.js `15.5.12` (App Router, Server Components + Client Components + API Routes + Server Actions)
- **UI Library**: React `19.2.4`, Tailwind CSS `3.4.1`, Radix UI (`dialog`, `dropdown-menu`, `label`, `progress`, `select`, `slot`, `tabs`), Lucide React `0.468.0`, Sonner `2.0.7` (Toast), Recharts `2.12.0`
- **Database & Auth**: Supabase (`@supabase/supabase-js` `2.39.3`, `@supabase/ssr` `0.5.2`) — PostgreSQL + Supabase Auth
- **Presisi Numerik**: `decimal.js` `10.4.3` (precision 10, `ROUND_HALF_UP`) + `round2` helper untuk konsistensi pembulatan
- **Export Engine**:
  - Excel: `xlsx` `0.18.5`
  - PDF: `jspdf` `2.5.1` + `jspdf-autotable` `3.8.2`
  - Word: `docx` `9.8.1`
- **Port Lokal Default**: `3002` (`npm run dev` → `next dev -p 3002`)

---

## 2. Struktur Direktori Utama

```text
JASPEL_Penuh2/
├── app/
│   ├── layout.tsx                    # RootLayout (Font Outfit, SettingsProvider, AuthErrorHandler, Toaster)
│   ├── globals.css                   # Design tokens CSS, .premium-gradient, .glass, .main-content
│   ├── login/                        # Halaman login
│   ├── forbidden/                    # Halaman 403 akses ditolak
│   ├── reset-password/               # Halaman reset password
│   ├── actions/                      # Global Server Actions (indicator-actions, sub-indicator-actions)
│   ├── (authenticated)/              # Grup rute terproteksi (Layout: SessionActivityManager + Sidebar + Footer)
│   │   ├── layout.tsx
│   │   ├── dashboard/                # Dashboard utama (Server Component + DashboardContent)
│   │   ├── units/                    # Master Unit Kerja + Period Locking Proporsi Unit
│   │   ├── pegawai/                  # Master Pegawai + Period Locking Snapshot Pegawai
│   │   ├── kpi-config/               # Konfigurasi KPI (Kategori P1/P2/P3, Indikator, Sub-Indikator, BPJS/UMUM)
│   │   ├── pool/                     # Manajemen Pool Insentif (BPJS, UMUM, Potongan, Approval)
│   │   ├── assessment/               # Penilaian KPI Pegawai (BPJS/UMUM, Bulk Copy, Copy BPJS→UMUM, Approval Lock)
│   │   ├── reports/                  # Laporan (Insentif, Pencapaian KPI, Perbandingan Unit, Slip Pegawai)
│   │   ├── users/                    # Manajemen Pengguna (Supabase Auth + Sinkronisasi Role)
│   │   ├── settings/                 # Pengaturan Sistem (Profil RS, Logo, Mekanisme Pajak Global, Footer)
│   │   ├── notifications/            # Pusat Notifikasi
│   │   ├── audit/                    # Audit Trail
│   │   ├── profile/                  # Profil Pengguna
│   │   └── realization/              # Import Realisasi Legacy
│   └── api/                          # 50+ REST API Endpoints (lihat Bagian 6)
├── components/                       # Komponen UI modular per domain (assessment, dashboard, kpi, pegawai, pool, units, users, auth, navigation, ui)
├── lib/
│   ├── contexts/settings-context.tsx # Context pengaturan aplikasi (client cache 10 menit)
│   ├── formulas/                     # kpi-calculator.ts, ter-lookup.ts (PP 58/2023)
│   ├── services/                     # dashboard.service.ts, rbac.service.ts, employee-period.service.ts, unit-period.service.ts, settings.service.ts, dll.
│   ├── supabase/                     # client.ts (browser singleton), server.ts (SSR + admin singleton), auth-helper.ts (local JWT decode)
│   └── utils/                        # score-calculator.ts, medical-unit.ts, server-cache.ts (LRU + in-flight dedupe), format.ts
├── services/
│   └── calculation.service.ts        # Service kalkulasi & validasi pool
├── supabase/migrations/              # Seluruh migrasi SQL DDL & constraint
├── middleware.ts                     # Route protection, RBAC, local JWT fast-path, security headers
└── next.config.js                    # Redirects (/ -> /login, /assesment -> /assessment), compress, serverActions 10mb
```

---

## 3. Sistem Autentikasi, RBAC & Keamanan Sesi

### 3.1 Role & Matriks Akses (`lib/services/rbac.service.ts` & `Sidebar.tsx`)

| Modul / Rute | `superadmin` | `unit_manager` | `employee` |
| :--- | :---: | :---: | :---: |
| `/dashboard` | Penuh (Semua Unit) | Terbatas Unit Sendiri | Skor & Ranking Pribadi |
| `/units` | Penuh (CRUD + Lock Periode) | Tidak ada | Tidak ada |
| `/pegawai` | Penuh (CRUD + Import + Lock Periode) | Tidak ada | Tidak ada |
| `/kpi-config` | Penuh (CRUD + Copy Struktur) | **Read-Only** (Unit Sendiri) | Tidak ada |
| `/pool` | Penuh (CRUD + Approve) | Lihat | Tidak ada |
| `/assessment` | Penuh (Semua Unit + Approve/Kunci Periode) | Penuh (**Isolasi Ketat Unit Sendiri**) | Tidak ada |
| `/reports` | Penuh (Semua Unit & Pegawai) | Terbatas **Unit Sendiri** | Tidak ada |
| `/users`, `/settings`, `/notifications`, `/audit` | Penuh | Tidak ada | Tidak ada |

- **Deteksi Superadmin**: Diakui jika `app_metadata.role === 'superadmin'`, atau `user_metadata.role === 'superadmin'`, atau `m_employees.role === 'superadmin'`, atau email `admin@sungaipenuh.com`.
- **Unit Khusus yang Dikecualikan dari Perhitungan**: Unit dengan `code` = `ADMIN` / `SUPERADMIN` atau `name` mengandung `SUPERADMIN`, serta pegawai dengan `role === 'superadmin'` selalu dikecualikan dari seluruh statistik Dashboard, daftar penilaian, dan perhitungan PIR/Insentif.

### 3.2 Middleware & Local JWT Verification (`middleware.ts`, `lib/supabase/auth-helper.ts`)
- Untuk menghindari rate limit Supabase Auth (`429`) dan menghemat egress:
  1. `middleware.ts` mengekstrak token dari cookie Supabase SSR (`extractTokenFromCookies`, mendukung chunked cookies `.0`, `.1`) lalu men-decode payload JWT lokal (`decodeJwtPayload`).
  2. Jika token lokal valid, **0 network call** dilakukan ke Supabase Auth API.
  3. Hanya jika token lokal tidak valid/expired baru memanggil `supabase.auth.getUser()`.
  4. Role pegawai di-cache di `LRUCache` (1000 entri, TTL 15 menit).
  5. Rute `/api/*`, `/_next/*`, dan aset statis dilewati dari matcher middleware (masing-masing API Route memverifikasi auth sendiri via `getAuthenticatedUser()`).
- **Security Headers**: `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-XSS-Protection: 1; mode=block`.

### 3.3 Manajemen Inaktivitas Sesi (`components/auth/SessionActivityManager.tsx`)
- **Idle Timeout**: 30 menit (`1.800.000 ms`).
- **Peringatan**: Muncul dialog modal pada menit ke-28 (2 menit tersisa) dengan countdown `mm menit ss detik`.
- **Grace Period**: Jika user kembali ke tab yang sudah idle ≥ 30 menit, diberi grace countdown 60 detik untuk menekan *"Lanjutkan Sesi"*.
- **Multi-Tab Sync**: Menggunakan `localStorage` key `jaspel_last_active_time` dan `jaspel_logout_event` agar aktivitas & logout tersinkronisasi antar tab.
- **Keep-Alive Hemat Egress**: Refresh sesi dibatasi setiap 15 menit saat aktif, dengan debounce minimal 5 menit saat berpindah tab (`focus` / `visibilitychange`).

---

## 4. Arsitektur Optimasi Egress Supabase (Free Tier < 5 GB)

Agar aplikasi tetap ringan dan aman di bawah kuota **5 GB Egress/bulan** pada Supabase Free Tier meski `t_kpi_assessments` memiliki puluhan/ratusan ribu baris:

1. **In-Flight Promise Deduplication & Server Cache (`lib/utils/server-cache.ts`)**:
   - `getOrSetCache(key, ttlMs, fetcher)` menyatukan request paralel untuk key yang sama menjadi 1 query DB saja (mencegah *cache stampede*).
   - `getCachedKpiMetadata(supabase)` men-cache seluruh `m_kpi_categories`, `m_kpi_indicators`, dan `m_kpi_sub_indicators` (~15 KB total, TTL 5 menit).
2. **Tanpa Nested Join pada Tabel Besar (`t_kpi_assessments`)**:
   - Query `t_kpi_assessments` di Dashboard, Assessment Reports, dan Report Generation hanya mengambil kolom flat minimal, lalu melakukan join dengan `indicatorsMap` & `subIndicatorsMap` di memori (menghemat 40–70% byte per query).
3. **Disable Eager Link Prefetching (`components/ui/optimized-link.tsx`)**:
   - Default `prefetch = false` pada link navigasi Sidebar mencegah Next.js mengeksekusi Server Component `/dashboard` secara otomatis di background.
4. **Agregat Per-Periode di Dashboard (`lib/services/dashboard.service.ts`)**:
   - Seluruh widget Dashboard (StatCard, Top/Worst Performers, Unit Performance, KPI Distribution, dan 6-Month Trend) berbagi cache agregat per-periode (TTL 5 menit), dan otomatis di-invalidate saat data penilaian disimpan/disalin.
5. **Unit-Scoped Filtering**:
   - API `/api/assessment/employees` dan `/api/assessment/status` menyaring `t_kpi_assessments` dengan `.in('employee_id', directEmpIds)` ketika jumlah pegawai ≤ 200 (mis. tampilan per unit / unit manager).
6. **Settings & Sidebar Caching**:
   - `/api/settings` menggunakan `createAdminClient()` singleton + server cache 10 menit + `Cache-Control: private, max-age=300`; client cache 10 menit; profil Sidebar di-cache di `sessionStorage` selama 5 menit.

---

## 5. Daftar Lengkap Halaman & API Endpoints

### 5.1 Halaman Utama (`app/`)
- **Publik**: `/login`, `/reset-password`, `/forbidden` (Redirect: `/` → `/login`, `/assesment` → `/assessment`, `/master-tarif` → `/dashboard`)
- **Terproteksi (`app/(authenticated)/`)**:
  - `/dashboard` — Statistik KPI, Tren 6 Bulan, Distribusi P1/P2/P3, Tabel Performa Unit, Top/Worst Performers
  - `/units` — Master Unit Kerja, Proporsi BPJS & UMUM, Period Locking Unit
  - `/pegawai` — Master Pegawai, Status Kepegawaian, PTKP, Golongan PNS, Rekening Bank, Status Kontrak, Import/Export Excel, Period Locking Pegawai
  - `/kpi-config` — Konfigurasi P1/P2/P3, Indikator (Indexing vs Prioritas), Sub-Indikator (Kuantitatif vs Kualitatif), Mode Skema (`same` vs `different`), Copy Struktur antar Unit / BPJS→UMUM
  - `/pool` — Pembuatan Pool Bulanan (Pendapatan BPJS, Pendapatan UMUM, Potongan), Alokasi %, Approval Pool, Export PDF Overview
  - `/assessment` — Penilaian Pegawai per Periode & Jenis Pendapatan (BPJS/UMUM), Status Kontrak/Sebagian, Salin Massal Periode Sebelumnya, Salin BPJS→UMUM, Approval/Kunci Periode
  - `/reports` — Generator 4 Jenis Laporan (`incentive`, `kpi-achievement`, `unit-comparison`, `employee-slip`), Export Excel & PDF, Download Petunjuk Penilaian PDF
  - `/users`, `/settings`, `/notifications`, `/audit`, `/profile`

### 5.2 API Endpoints (`app/api/`)

| Grup | Endpoint | Method | Fungsi |
| :--- | :--- | :--- | :--- |
| **Assessment** | `/api/assessment` | GET, POST, PUT | Ambil & simpan penilaian indikator + sub-indikator (otomatis mirror ke `t_realization` & invalidate cache) |
| | `/api/assessment/employees` | GET | Daftar pegawai + status kelengkapan indikator + summary (unit-scoped & cached) |
| | `/api/assessment/status` | GET | Status penyelesaian penilaian per unit/pegawai |
| | `/api/assessment/indicators` | GET | Struktur kategori, indikator & sub-indikator + nilai tersimpan untuk dialog penilaian |
| | `/api/assessment/previous` | GET | Ambil nilai penilaian periode sebelumnya untuk 1 pegawai |
| | `/api/assessment/bulk-copy` | POST | Salin massal penilaian 1 unit dari periode sebelumnya ke periode terpilih |
| | `/api/assessment/copy-bpjs-to-umum` | POST | Salin penilaian non-prioritas dari BPJS ke UMUM untuk 1 unit |
| | `/api/assessment/period-approval` | GET, POST | Cek & ubah status kunci/persetujuan periode (Superadmin) |
| | `/api/assessment/reports` | GET | Action: `periods`, `units`, `report`, `comparison` |
| | `/api/assessment/export` | GET | Export rekap penilaian |
| **Reports** | `/api/reports/generate` | POST | Engine kalkulasi utama: `incentive`, `kpi-achievement`, `unit-comparison`, `employee-slip` |
| | `/api/reports/generate/metadata` | GET | Daftar unit & pegawai (snapshot-aware) untuk filter laporan |
| | `/api/reports/export` | POST | Export hasil laporan ke Excel / PDF |
| | `/api/reports/assessment-guide` | POST | Generate PDF Petunjuk Penilaian KPI per unit |
| **Dashboard** | `/api/dashboard/stats`, `performance`, `top-performers`, `activities`, `export` | GET/POST | Endpoint data & export dashboard |
| **KPI Config** | `/api/kpi-config`, `/category`, `/copy-structure`, `/export`, `/guide` | GET/POST | Manajemen & ekspor konfigurasi KPI |
| **Master Data** | `/api/units/[id]`, `/import`, `/export`, `/template` | GET/POST/PUT/DELETE | CRUD & Import/Export Unit |
| | `/api/pegawai/import`, `/export`, `/template` | GET/POST | Import/Export Pegawai |
| | `/api/users`, `/list`, `/create`, `/update`, `/delete`, `/import`, `/export`, `/sync-role` | GET/POST/PUT/DELETE | Manajemen akun Auth + Pegawai |
| **Medis & Lain** | `/api/remuneration/medis` | GET, POST | CRUD Guarantee Fee dokter (`remunerasi_master_dokter`) |
| | `/api/settings`, `/api/profile`, `/api/notifications`, `/api/audit`, `/api/health` | GET/PATCH | Pengaturan sistem, profil, notifikasi, audit log, health check |

---

## 6. Panduan Replikasi / Copying Aplikasi (Step-by-Step)

Agar instance baru **100% identik** dengan aplikasi ini:

### Langkah 1: Persiapan Environment Variables (`.env.local`)
```env
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
NEXT_PUBLIC_APP_URL=http://localhost:3002
```

### Langkah 2: Setup Database Supabase
1. Buat project Supabase baru (PostgreSQL 15+).
2. Jalankan migrasi SQL dari folder `supabase/migrations/` secara berurutan (detail struktur tabel & index wajib ada di [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)).
3. Pastikan **Unique Index 5-kolom** pada `t_kpi_assessments` terpasang agar `upsert` penilaian & bulk-copy tidak menghasilkan duplikasi:
   ```sql
   CREATE UNIQUE INDEX IF NOT EXISTS t_kpi_assessments_unique_key
   ON t_kpi_assessments (employee_id, indicator_id, period, COALESCE(sub_indicator_id, '00000000-0000-0000-0000-000000000000'), revenue_type);
   ```
4. Pastikan row default `t_settings` terisi (`company_info`, `footer`, `tax_config`, `tax_rates`, `calculation_params`, `session_timeout`).

### Langkah 3: Konfigurasi Unit Khusus (`lib/utils/medical-unit.ts`)
- Jika UUID unit di database baru berbeda dengan database lama, **identifikasi berdasarkan nama unit tetap bekerja otomatis**:
  - Unit Medis: nama persis `MEDIS` atau diawali `MEDIS ` (tidak termasuk `REKAM MEDIS`).
  - Unit Eligible Fitur "Sebagian" (Parsial): nama mengandung `KEPERAWATAN`, `RADIOLOGI`, `REKAM MEDIK`, atau `REKAM MEDIS`.
- Opsional: perbarui konstanta `MEDICAL_UNIT_ID` dan `PARTIAL_ELIGIBLE_UNIT_IDS` di `lib/utils/medical-unit.ts` agar sesuai UUID baru.

### Langkah 4: Setup Superadmin & Jalankan Aplikasi
```bash
npm install
npm run validate:env
npm run setup:auth
npm run build
npm run start        # Produksi di port 3002
# atau untuk pengembangan:
npm run dev          # Dev di port 3002
```

### Langkah 5: Checklist Verifikasi Paritas (Wajib)
1. Login sebagai Superadmin dan Unit Manager → pastikan isolasi unit berjalan di Dashboard, Penilaian, dan Laporan.
2. Uji 1 periode penuh (BPJS & UMUM) → pastikan di halaman `/reports` (Laporan Insentif per Unit) muncul badge hijau:
   `✓ Insentif Bruto Sama Persis dengan Alokasi Unit (Selisih: Rp 0,00)`.
3. Uji Unit Medis (metode SUM + Kontrak %) dan Unit Non-Medis (metode Weighted + Prioritas + Potongan + Distribusi Potongan).
4. Uji ketiga mekanisme pajak (`ter`, `final_pp80`, `none`) di menu `/settings`.

