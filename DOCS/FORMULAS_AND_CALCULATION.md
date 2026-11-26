# Spesifikasi Rumus & Kalkulasi 100% Eksak — PINTAR JP

Dokumen ini menjabarkan **seluruh rumus matematika dan logika bisnis** yang digunakan di aplikasi secara presisi (mengikuti kode sumber di `app/api/reports/generate/route.ts`, `lib/utils/score-calculator.ts`, `lib/utils/medical-unit.ts`, dan `lib/formulas/ter-lookup.ts`).

---

## 1. Identifikasi Unit Khusus (`lib/utils/medical-unit.ts`)

1. **Unit Medis (`isMedicalUnit`)**:
   - Bernilai `true` jika `unitId === '8914356c-4ec8-4bd7-bc5e-5fb619f6c3f2'`, **ATAU** `unitName.toUpperCase().trim() === 'MEDIS'`, **ATAU** diawali `'MEDIS '` (contoh: `'MEDIS - DOKTER'`).
   - **Pengecualian eksplisit**: `'REKAM MEDIS'` / `'REKAM MEDIK'` **BUKAN** Unit Medis.
2. **Unit Eligible Fitur Sebagian/Parsial (`isPartialEligibleUnit`)**:
   - Bernilai `true` jika unit adalah **KEPERAWATAN**, **RADIOLOGI**, atau **REKAM MEDIK / REKAM MEDIS** (berlaku untuk pendapatan `bpjs` maupun `umum`).

---

## 2. Rumus Pool & Alokasi Dana Unit

### 2.1 Perhitungan Pool (`PoolFormDialog.tsx`)
$$\text{Revenue BPJS} = \sum \text{Item Revenue (BPJS)}$$
$$\text{Revenue UMUM} = \sum \text{Item Revenue (UMUM)}$$
$$\text{Allocated BPJS} = \text{Revenue BPJS} \times \frac{\text{Allocation \% BPJS}}{100}$$
$$\text{Allocated UMUM} = \text{Revenue UMUM} \times \frac{\text{Allocation \% UMUM}}{100}$$
$$\text{Revenue Total} = \text{Revenue BPJS} + \text{Revenue UMUM}$$
$$\text{Net Pool} = \text{Revenue Total} - \text{Deduction Total}$$

### 2.2 Resolusi Dana Pool pada Laporan (`generateIncentiveReport`)
- Jika `revenueType === 'bpjs'`: `netPool = revenue_bpjs || allocated_bpjs || net_pool`
- Jika `revenueType === 'umum'`: `netPool = revenue_umum || allocated_umum || net_pool`
- Jika `revenueType === 'all'`: `netPool = revenue_total || net_pool`

### 2.3 Alokasi Unit (`allocatedForUnit`)
Menggunakan proporsi dari `t_unit_period_snapshots` (jika periode terkunci/ada snapshot), atau fallback ke `m_units`:
- Jika `revenueType === 'bpjs'`: `unitProp = proportion_percentage`
- Jika `revenueType === 'umum'`:
  - Jika `use_same_proportion === true` → `unitProp = proportion_percentage`
  - Jika `use_same_proportion === false` → `unitProp = proportion_umum_percentage`

$$\text{Alokasi Unit} = \text{netPool} \times \frac{\text{unitProp}}{100}$$

---

## 3. Rumus Penilaian Sub-Indikator & Indikator

### 3.1 Nilai Efektif Sub-Indikator (`subScoreMap`)
Setiap sub-indikator dideduplikasi berdasarkan `(employee_id, indicator_id, sub_indicator_id)` dengan mengambil record terbaru (`updated_at`).

1. **Sub-Indikator Kuantitatif (`measurement_type === 'quantitative'`)**:
   $$\text{realScore} = \text{realization\_value} \times \text{base\_index\_value}$$
   - Jika `tariff != 1` dan `effectiveScore != realScore` (atau `effectiveScore == 0`), maka `effectiveScore = realScore`.
2. **Sub-Indikator Kualitatif (`measurement_type !== 'quantitative'`)**:
   - **Jika Indikator Induk bertipe `priority`**:
     - `realVal = (score != null && score != 0) ? score : realization_value`
     - Jika `subBase > 1 && realVal < subBase && realVal <= 10`: `effectiveScore = realVal * subBase`
     - Selain itu: `effectiveScore = realVal` *(mencegah pengkuadratan nominal besar seperti Rp 100.000 × 100.000)*.
   - **Jika Indikator Induk Non-Prioritas**:
     - **Unit Medis**: `effectiveScore = rawScore * 1`
     - **Unit Non-Medis**: `effectiveScore = rawScore * (sub_weight_percentage / 100)`
3. **Agregasi ke Indikator Induk**:
   $$\text{subScoreMap}[emp, ind] = \sum_{\text{sub}} \text{effectiveScore}_{\text{sub}}$$

### 3.2 Resolusi Nilai Efektif Indikator Utama (`indicatorScore`)
Urutan prioritas resolusi:
1. Jika memiliki agregat sub-indikator (`subAgg.score > 0`) → pakai `subAgg.score`.
2. Jika kolom `score` di DB terisi dan `!= 0` → pakai `parseFloat(score)`.
3. Jika `subAgg` terdefinisi (meski 0) → pakai `subAgg.score`.
4. Jika `isActivity` (`calculation_method === 'priority'` atau `configuration_style === 'activity'`):
   - Jika `base_index_value > 0` → `realization_value * base_index_value`, else `realization_value`.
5. Jika `target_value > 0`:
   $$\text{achPct} = \min\left(100,\; \frac{\text{realization\_value}}{\text{target\_value}} \times 100\right)$$
   - Unit Medis: `indicatorScore = achPct`
   - Unit Non-Medis: `indicatorScore = achPct * (indWeight / 100)`
6. Jika `target_value === 0` (indikator kualitatif):
   - Unit Medis: `indicatorScore = realization_value`
   - Unit Non-Medis: `indicatorScore = realization_value * (indWeight / 100)`

### 3.3 Klasifikasi Indikator: Indeks vs Prioritas vs Potongan
- **Potongan (`isDeduction`)**: Jika `indicatorScore < 0` → masuk ke `totalDeductionRupiah += |indicatorScore|` (TIDAK masuk skor indeks maupun prioritas).
- **Insentif Prioritas (`isPriority && !isDeduction`)**: Jika `calculation_method === 'priority'` dan `indicatorScore >= 0` → masuk ke `priorityScore` & `totalActivityRupiah` (nominal Rupiah langsung, TIDAK masuk skor indeks).
- **Indikator Indeks (Standar)**: Masuk ke akumulasi skor kategori P1 / P2 / P3.

---

## 4. Rumus Skor Kategori (P1, P2, P3) & Total Indeks

### 4.1 Pada Laporan Insentif (`app/api/reports/generate/route.ts`)
Untuk setiap kategori (`P1`, `P2`, `P3`):
- Jika kategori berbobot (`is_weighted !== false`):
  $$\text{totalRealisasiKategori} = \sum (\text{indicatorScore} \times \frac{\text{indWeight}}{100})$$
  $$\text{totalTargetKategori} = \sum (\text{indTarget} \times \frac{\text{indWeight}}{100})$$
- Jika kategori tidak berbobot (`is_weighted === false`):
  $$\text{totalRealisasiKategori} = \sum \left(\text{indTarget} > 0 \;?\; \frac{\text{indicatorScore}}{\text{indTarget}} \times 100 \;:\; \text{indicatorScore}\right), \quad \text{totalTargetKategori} = \sum 100$$

Konversi menjadi `kontribusiAkhir`:
- Jika `totalTargetKategori > 0`:
  - Berbobot: $\text{kontribusiAkhir} = \frac{\text{totalRealisasiKategori}}{\text{totalTargetKategori}} \times \text{categoryWeight}$
  - Tidak Berbobot: $\text{kontribusiAkhir} = \frac{\text{totalRealisasiKategori}}{\text{totalTargetKategori}} \times 100$
- Jika `totalTargetKategori === 0`:
  - Berbobot: $\text{kontribusiAkhir} = \text{totalRealisasiKategori} \times \frac{\text{categoryWeight}}{100}$
  - Tidak Berbobot: $\text{kontribusiAkhir} = \text{totalRealisasiKategori}$

**Perbedaan Medis vs Non-Medis**:
- **Unit Medis**: $\text{indexScore}_{\text{cat}} = \text{totalRealisasiKategori}$
- **Unit Non-Medis**: $\text{indexScore}_{\text{cat}} = \text{kontribusiAkhir}$

### 4.2 Pengali Status Kontrak (Medis) & Sebagian/Parsial (Keperawatan, Radiologi, Rekam Medik)
Jika pegawai memiliki `is_contract === true` pada Unit Medis atau Unit Parsial:
$$\text{contractMultiplier} = \frac{\max(0,\; \text{contract\_percentage})}{100}$$
$$P_1 = \text{round2}(\text{indexScore}_{P1} \times \text{contractMultiplier})$$
$$P_2 = \text{round2}(\text{indexScore}_{P2} \times \text{contractMultiplier})$$
$$P_3 = \text{round2}(\text{indexScore}_{P3} \times \text{contractMultiplier})$$
$$\text{Total Indeks} = \text{round2}(P_1 + P_2 + P_3)$$
*(Catatan: `round2(x) = Math.round((x + 1e-9) * 100) / 100`. Pengali kontrak/parsial HANYA berlaku pada skor indeks, TIDAK memotong Insentif Prioritas).*

### 4.3 Pada Dashboard (`lib/utils/score-calculator.ts` & `dashboard.service.ts`)
Digunakan untuk ringkasan performa KPI (mengecualikan indikator `priority`):
- **Kategori**:
  - Medis: $\text{CategoryScore} = \sum \text{scores}$
  - Non-Medis: $\text{CategoryScore} = \frac{\sum \text{scores}}{n}$
- **Total Skor Dashboard**:
  - Medis: $\text{Total} = (P_1 + P_2 + P_3) \times \frac{\text{contractPercentage}}{100}$
  - Non-Medis: $\text{Total} = \frac{P_1 + P_2 + P_3}{3}$

---

## 5. Rumus PIR, Potongan, Distribusi Potongan & Insentif Bruto

### 5.1 Total Indeks Kolektif Unit
$$\text{Total Skor Unit} = \sum_{i \in \text{Unit}} \text{Total Indeks}_i \quad (\text{dibulatkan 2 desimal})$$

### 5.2 PIR (Poin Indeks Rupiah) per Unit
Disimpan dengan **presisi penuh (full floating-point precision)** selama kalkulasi agar tidak terjadi deviasi nominal besar:
- **Unit Medis**:
  $$\text{Sisa Pagu Medis} = \text{Alokasi Unit} - \sum \text{Guarantee Fee Dokter} - \sum \text{Insentif Prioritas Unit}$$
  $$\text{PIR}_{\text{Medis}} = \begin{cases} \dfrac{\text{Sisa Pagu Medis}}{\text{Total Skor Unit}} & \text{jika } \text{Total Skor Unit} > 0 \text{ dan } \text{Sisa Pagu Medis} > 0 \\ 0 & \text{lainnya} \end{cases}$$
- **Unit Non-Medis (Standar)**:
  $$\text{PIR}_{\text{Standar}} = \max\left(0,\; \frac{\text{Alokasi Unit} - \sum \text{Insentif Prioritas Unit}}{\text{Total Skor Unit}}\right)$$

### 5.3 Redistribusi Potongan Unit (`distribusi_potongan`)
Seluruh potongan negatif pegawai dalam 1 unit dikumpulkan lalu dibagikan **sama rata** kepada pegawai di unit yang sama yang **tidak terkena potongan** (`potongan === 0`):
$$\text{Total Potongan Unit} = \sum_{i \in \text{Unit}} \text{Potongan}_i$$
$$N_{\text{non-potong}} = N_{\text{total unit}} - N_{\text{terpotong}}$$
$$\text{Distribusi Potongan}_i = \begin{cases} \dfrac{\text{Total Potongan Unit}}{N_{\text{non-potong}}} & \text{jika } \text{Potongan}_i = 0 \text{ dan } N_{\text{non-potong}} > 0 \\ 0 & \text{jika } \text{Potongan}_i > 0 \end{cases}$$

### 5.4 Insentif Bruto Pegawai
$$\text{Insentif Indeks}_i = \text{round2}(\text{Total Indeks}_i \times \text{PIR}_{\text{unit}})$$
$$\text{Bruto Sebelum Potongan}_i = \text{Insentif Indeks}_i + \text{Insentif Prioritas}_i + \text{Distribusi Potongan}_i + \text{Guarantee Fee}_i$$
$$\text{Insentif Bruto}_i = \max\left(0,\; \text{Bruto Sebelum Potongan}_i - \text{Potongan}_i\right)$$

### 5.5 Rekonsiliasi Pembulatan Alokasi Unit (Selisih Rp 0,00)
Saat laporan penuh 1 unit digenerate (bukan filter 1 pegawai):
$$\text{diff} = \text{round2}\left(\text{Alokasi Unit} - \sum_{i \in \text{Unit}} \text{Insentif Bruto}_i\right)$$
- Jika $0 < |\text{diff}| < 50$ (selisih pembulatan sen), maka `diff` ditambahkan ke pegawai dengan **`total_score` tertinggi** di unit tersebut (menyesuaikan `gross_incentive`, `index_incentive`, lalu menghitung ulang PPh 21 & `net_incentive` pegawai tersebut).
- Hasilnya: $\sum \text{Insentif Bruto} \equiv \text{Alokasi Unit}$ dengan selisih **Rp 0,00**.

---

## 6. Rumus Pajak PPh 21 & Insentif Netto

Mekanisme pajak dikontrol secara global melalui `t_settings` (`key = 'tax_config'`):

### 6.1 Opsi 1: `none` (Tanpa Potongan)
$$\text{PPh 21} = 0$$

### 6.2 Opsi 2: `final_pp80` (PPh 21 Final — PP 80/2010)
- **PPPK** dan **BLUD** → `0%`
- **ASN / PNS** berdasarkan `pns_grade`:
  - Golongan **IV** (`IV/*` atau `4*`) → `Math.round(Bruto × 0.15)` (**15%**)
  - Golongan **III** (`III/*` atau `3*`) → `Math.round(Bruto × 0.05)` (**5%**)
  - Golongan **I & II** (`I/*`, `II/*`, `1*`, `2*`) → **0%**
  - ASN/PNS tanpa golongan (fallback) → **5%**

### 6.3 Opsi 3: `ter` (Tarif Efektif Rata-rata — PP 58/2023, Default)
1. **Pemetaan PTKP → Kategori TER (`getTERCategory`)**:
   - **Kategori A**: `TK/0`, `TK/1`, `K/0` *(default jika tidak dikenal)* — 44 lapisan (0% s/d Rp 5.400.000 hingga 34% di atas Rp 1.419.000.000)
   - **Kategori B**: `TK/2`, `TK/3`, `K/1`, `K/2` — 40 lapisan (0% s/d Rp 6.200.000 hingga 34% di atas Rp 1.405.000.000)
   - **Kategori C**: `K/3` — 41 lapisan (0% s/d Rp 6.600.000 hingga 34% di atas Rp 1.419.000.000)
2. **Lookup Tarif (`getTERRate`)**: Mencari bracket pertama dimana `monthlyGross <= bracket.limit` di `lib/formulas/ter-lookup.ts`.
3. **Perhitungan Pajak**:
   $$\text{PPh 21} = \text{Math.round}\left(\frac{\text{Insentif Bruto} \times \text{ratePercentage}}{100}\right)$$

### 6.4 Insentif Netto
$$\text{Insentif Netto} = \text{Insentif Bruto} - \text{PPh 21}$$

---

## 7. Aturan Fallback Silang BPJS ↔ UMUM

- Untuk unit dengan `kpi_schema_mode !== 'different'` (mode `'same'`):
  - Jika pegawai belum memiliki nilai di jenis pendapatan yang diminta (mis. UMUM), atau nilai realisasinya `0` sementara pada jenis pendapatan lawannya (BPJS) bernilai `!= 0` (termasuk potongan), sistem otomatis mengambil nilai dari jenis pendapatan lawan sebagai fallback.
- Untuk unit dengan `kpi_schema_mode === 'different'`:
  - **Tidak ada fallback silang**; indikator BPJS dan UMUM dipisahkan secara ketat sesuai `m_kpi_categories.revenue_type`.

