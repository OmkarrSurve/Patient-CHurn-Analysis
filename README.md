# 🏥 Hospital Patient Churn Analysis & Risk Segmentation

> An end-to-end data analytics project to identify and segment patients at risk of not returning to a hospital, using PostgreSQL, Excel and Power BI.

---

## 📌 Table of Contents

- [Project Overview](#project-overview)
- [Problem Statement](#problem-statement)
- [Tools & Technologies](#tools--technologies)
- [Dataset](#dataset)
- [Project Architecture](#project-architecture)
- [Phase 1 — PostgreSQL: Data Engineering](#phase-1--postgresql-data-engineering)
- [Phase 2 — Excel: RFM Scoring & Segmentation](#phase-2--excel-rfm-scoring--segmentation)
- [Phase 3 — Power BI: Dashboard & Visuals](#phase-3--power-bi-dashboard--visuals)
- [Churn Definition](#churn-definition)
- [RFM Model Explained](#rfm-model-explained)
- [Risk Segments](#risk-segments)
- [Key Insights](#key-insights)
- [Project Structure](#project-structure)
- [How to Run](#how-to-run)
- [Limitations & Future Work](#limitations--future-work)

---

## Project Overview

Patient churn — where patients stop returning to a hospital — is a significant challenge for healthcare providers. Losing patients means lost revenue, reduced continuity of care, and poorer health outcomes for patients who needed follow-up treatment.

This project builds a complete analytics pipeline that:
- Ingests and stores raw hospital admission data in PostgreSQL
- Engineers churn-relevant features using SQL
- Scores patients using an RFM (Recency, Frequency, Monetary) model in Excel
- Visualises risk segments and actionable insights in a Power BI dashboard

---

## Problem Statement

> *"Which patients are at risk of never returning to the hospital, and what actions should the hospital take to retain them?"*

Hospitals typically treat a patient and discharge them without any systematic way of knowing whether that patient will come back. This project addresses that gap by analysing historical admission data to identify behavioural patterns that indicate patient disengagement.

---

## Tools & Technologies

| Tool | Version | Purpose |
|---|---|---|
| PostgreSQL | 18 | Data storage, SQL queries, feature engineering |
| pgAdmin 4 | Latest | PostgreSQL GUI client |
| Microsoft Excel | 2019/365 | RFM scoring, churn formulas, pivot validation |
| Power BI Desktop | Latest | Interactive dashboard and visualisations |
| Python | 3.x | Synthetic data generation |
| Git & GitHub | — | Version control and project sharing |

---

## Dataset

Since no suitable public dataset existed with multiple visits per patient, a **synthetic dataset** was generated using Python to simulate realistic hospital behaviour.

| Attribute | Value |
|---|---|
| Total rows | 50,000 admissions |
| Unique patients | ~7,057 |
| Date range | January 2019 – June 2024 |
| Avg visits per patient | 7.09 |
| Min visits per patient | 2 |
| Max visits per patient | 15 |
| Churner ratio | ~40% churned / 60% active |

### Columns

| Column | Description |
|---|---|
| `patient_id` | Unique identifier per patient |
| `name` | Patient name |
| `age` | Age at time of admission |
| `gender` | Male / Female |
| `blood_type` | A+, A-, B+, B-, O+, O-, AB+, AB- |
| `medical_condition` | Primary diagnosis (e.g. Diabetes, Hypertension) |
| `date_of_admission` | Date patient was admitted |
| `doctor` | Treating doctor |
| `hospital` | Hospital name |
| `insurance_provider` | Patient's insurance company |
| `billing_amount` | Total bill for the admission (INR) |
| `room_number` | Assigned room |
| `admission_type` | Elective / Emergency / Urgent |
| `discharge_date` | Date patient was discharged |
| `medication` | Primary medication prescribed |
| `test_results` | Normal / Abnormal / Inconclusive |

---

## Project Architecture

```
Raw CSV (50k rows)
       │
       ▼
┌─────────────────┐
│   PostgreSQL    │  ← CREATE TABLE, import via pgAdmin
│                 │
│   healthcare    │  ← Raw 50,000 admission rows
│  patient_visits │  ← Aggregated per patient
│  churn_flagged  │  ← is_churned = 0 or 1
│  rfm_scored     │  ← Recency, Frequency, Monetary scores
└────────┬────────┘
         │ Export CSV
         ▼
┌─────────────────┐
│     Excel       │  ← Risk Segment formula
│                 │  ← Churn Probability formula
│  churn_model    │  ← Pivot table validation
└────────┬────────┘
         │ Import .xlsx
         ▼
┌─────────────────┐
│    Power BI     │  ← DAX measures
│                 │  ← 4 dashboard pages
│   Dashboard     │  ← Conditional formatting by risk
└─────────────────┘
```

---

## Phase 1 — PostgreSQL: Data Engineering

All SQL is in `sql/hospital_churn.sql`. Run the file top to bottom in pgAdmin.

### Step 1: Create the healthcare table

```sql
CREATE TABLE healthcare (
    patient_id         INT,
    name               VARCHAR(100),
    age                INT,
    gender             VARCHAR(10),
    blood_type         VARCHAR(5),
    medical_condition  VARCHAR(100),
    date_of_admission  DATE,
    doctor             VARCHAR(100),
    hospital           VARCHAR(100),
    insurance_provider VARCHAR(50),
    billing_amount     NUMERIC(10,2),
    room_number        INT,
    admission_type     VARCHAR(20),
    discharge_date     DATE,
    medication         VARCHAR(100),
    test_results       VARCHAR(20)
);
```

Import the CSV via pgAdmin: right-click `healthcare` → **Import/Export Data** → Format: CSV, Header: ON.

### Step 2: Build patient-level visit history

Each patient has multiple rows in `healthcare` (one per admission). This query collapses them into one row per patient with aggregated features.

```sql
CREATE TABLE patient_visits AS
SELECT
    name, age, gender, insurance_provider, medical_condition,
    COUNT(*)                             AS total_admissions,
    MIN(date_of_admission)               AS first_admission,
    MAX(date_of_admission)               AS last_admission,
    MAX(discharge_date)                  AS last_discharge,
    (CURRENT_DATE - MAX(discharge_date)) AS days_since_last_visit,
    SUM(billing_amount)                  AS total_billing,
    AVG(billing_amount)                  AS avg_billing,
    SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END) AS emergency_count,
    SUM(CASE WHEN test_results = 'Abnormal'    THEN 1 ELSE 0 END) AS abnormal_tests
FROM healthcare
GROUP BY name, age, gender, insurance_provider, medical_condition;
```

### Step 3: Apply churn definition

A patient is churned if their last discharge was more than 180 days before the dataset's end date. We use the dataset's own `MAX(discharge_date)` as the reference point instead of `CURRENT_DATE` — this avoids marking every patient as churned when running the query years after the data ends.

```sql
CREATE TABLE churn_flagged AS
SELECT *,
    CASE
        WHEN last_discharge < (
            (SELECT MAX(discharge_date) FROM healthcare) - INTERVAL '180 days'
        )
        THEN 1 ELSE 0
    END AS is_churned
FROM patient_visits;
```

### Step 4: RFM scoring

Each patient gets three scores (1–5) across Recency, Frequency and Monetary dimensions.

```sql
CREATE TABLE rfm_scored AS
SELECT *,
    -- Recency score: how recently did the patient last visit?
    CASE
        WHEN days_since_last_visit <= 180  THEN 5   -- last 6 months
        WHEN days_since_last_visit <= 365  THEN 4   -- last 1 year
        WHEN days_since_last_visit <= 730  THEN 3   -- last 2 years
        WHEN days_since_last_visit <= 1095 THEN 2   -- last 3 years
        ELSE 1                                       -- 3+ years ago
    END AS recency_score,

    -- Frequency score: how many times has the patient been admitted?
    CASE
        WHEN total_admissions >= 9 THEN 5
        WHEN total_admissions >= 7 THEN 4
        WHEN total_admissions >= 4 THEN 3
        WHEN total_admissions >= 2 THEN 2
        ELSE 1
    END AS frequency_score,

    -- Monetary score: how much has the patient spent in total?
    CASE
        WHEN total_billing >= 150000 THEN 5
        WHEN total_billing >= 100000 THEN 4
        WHEN total_billing >= 70000  THEN 3
        WHEN total_billing >= 30000  THEN 2
        ELSE 1
    END AS monetary_score

FROM churn_flagged;
```

### Step 5: Final export query

This is the query whose results are exported to Excel as `churn_model.csv`.

```sql
SELECT
    name, age, gender, insurance_provider, medical_condition,
    total_admissions, first_admission, last_admission, days_since_last_visit,
    ROUND(total_billing::NUMERIC, 2) AS total_billing,
    ROUND(avg_billing::NUMERIC, 2)   AS avg_billing,
    emergency_count, abnormal_tests,
    is_churned, recency_score, frequency_score, monetary_score,
    ROUND(
        ((recency_score * 0.40) + (frequency_score * 0.35) + (monetary_score * 0.25))::NUMERIC
    , 2) AS churn_score
FROM rfm_scored
ORDER BY churn_score ASC;
```

> Export: Select every column from the results along with the entire data values and paste it in excel.

---

## Phase 2 — Excel: RFM Scoring & Segmentation

Open Excel, Paste the final result save as `churn_model.csv`. Add two new columns at the end:

### Risk Segment
```excel
=IF(R2>=4.0,"Low Risk",IF(R2>=3.0,"Medium Risk",IF(R2>=2.0,"High Risk","Critical")))
```

### Churn Probability %
```excel
=IF(S2="Critical",95,IF(S2="High Risk",70,IF(S2="Medium Risk",40,10)))
```

Drag both formulas down to the last row.

### Pivot Table (validation)
- **Insert → PivotTable**
- Rows: `Risk Segment`
- Columns: `insurance_provider`
- Values: Count of patients, Average churn_score, Sum of total_billing

---

## Phase 3 — Power BI: Dashboard & Visuals

**Connect:** Home → Get Data → Excel → select `churn_model.xlsx`

### DAX Measures

```dax
Total Patients = COUNTROWS(churn_model)

Churned Patients =
CALCULATE(COUNTROWS(churn_model), churn_model[is_churned] = 1)

Active Patients =
CALCULATE(COUNTROWS(churn_model), churn_model[is_churned] = 0)

Churn Rate % =
ROUND(DIVIDE([Churned Patients], [Total Patients]) * 100, 1)

Revenue at Risk =
CALCULATE(
    SUM(churn_model[total_billing]),
    churn_model[Risk Segment] IN {"High Risk", "Critical"}
)

Avg Days Since Visit =
ROUND(AVERAGE(churn_model[days_since_last_visit]), 0)
```

## Churn Definition

```
Reference date  =  MAX(discharge_date) from dataset  =  2024-06-06
Churn cutoff    =  2024-06-06 − 180 days             =  2023-12-08

last_discharge BEFORE 2023-12-08  →  is_churned = 1  (churned)
last_discharge AFTER  2023-12-08  →  is_churned = 0  (active)
```

> `CURRENT_DATE` was intentionally avoided — the dataset ends in 2024 so using today's date would mark every single patient as churned.

---

## RFM Model Explained

RFM is a proven customer analytics framework adapted here for healthcare:

| Dimension | Definition | Weight | Rationale |
|---|---|---|---|
| **Recency** | Days since last discharge | 12.5% | Most important — recent patients are most re-engageable |
| **Frequency** | Total number of admissions | 36% | Frequent patients show hospital loyalty |
| **Monetary** | Total billing amount (INR) | 30% | High-value patients worth prioritising for retention |

### Recency Score Thresholds

| Days Since Last Visit | Score |
|---|---|
| ≤ 180 days (6 months) | 5 |
| ≤ 365 days (1 year) | 4 |
| ≤ 730 days (2 years) | 3 |
| ≤ 1095 days (3 years) | 2 |
| > 1095 days | 1 |

### Frequency Score Thresholds

| Total Admissions | Score |
|---|---|
| 9 or more | 5 |
| 7 – 8 | 4 |
| 4 – 6 | 3 |
| 2 – 3 | 2 |
| 1 | 1 |

### Monetary Score Thresholds

| Total Billing (INR) | Score |
|---|---|
| ≥ 1,50,000 | 5 |
| ≥ 1,00,000 | 4 |
| ≥ 70,000 | 3 |
| ≥ 30,000 | 2 |
| < 30,000 | 1 |

### Final Churn Score Formula

```
Churn Score = (Recency × 0.40) + (Frequency × 0.35) + (Monetary × 0.25)
```

Higher score = lower churn risk. Lower score = higher churn risk.

---

## Risk Segments

| Segment | Churn Score | Churn Probability | Recommended Action |
|---|---|---|---|
| 🟢 Low Risk | ≥ 4.0 | 10% | Loyalty nudge, health checkup reminder |
| 🟡 Medium Risk | ≥ 3.0 | 40% | Appointment reminder 30 days out |
| 🟠 High Risk | ≥ 2.0 | 70% | Doctor sends personalised follow-up |
| 🔴 Critical | < 2.0 | 95% | Immediate SMS / call re-engagement |

---

## Key Insights

- Patients with **Emergency admissions** had higher churn — likely discharged without adequate follow-up
- **Chronic condition patients** (Diabetes, Hypertension) who churned represent the highest revenue risk
- Patients with **Abnormal test results** who churned are a clinical concern beyond just revenue
- **Low frequency patients** (1–2 visits) dominate the Critical segment

---

## Project Structure

```
hospital-churn-prediction/
│
├── data/
│   └── hospital_churn_data.csv        ← 50,000 row synthetic dataset
│
├── sql/
│   └── hospital_churn.sql             ← All queries in one file (run top to bottom)
│
├── excel/
│   └── churn_model.csv               ← Risk segment + probability columns + pivot
│
├── powerbi/
│   └── hospital_churn_dashboard.pbix  ← Full Power BI dashboard
│
└── README.md
```

---

## How to Run

### 1. Set up PostgreSQL
- Install PostgreSQL and pgAdmin
- Create a new database called `hospital_churn`

### 2. Load the data
- Run the `CREATE TABLE healthcare` block from `sql/hospital_churn.sql`
- Right-click `healthcare` in pgAdmin → **Import/Export Data**
- Import `data/hospital_churn_data.csv` — Format: CSV, Header: ON, Delimiter: `,`

### 3. Run remaining SQL
- Continue running `sql/hospital_churn.sql` from top to bottom
- All four tables will be created in order: `healthcare` → `patient_visits` → `churn_flagged` → `rfm_scored`

### 4. Export to Excel
- Run the final SELECT query at the bottom of the SQL file
- Right-click results in pgAdmin → **Download as CSV** → save as `churn_model.csv`
- Open in Excel, add `Risk Segment` and `Churn Probability` columns using the formulas above
- Save as `churn_model.xlsx`

### 5. Open Power BI
- Open `powerbi/hospital_churn_dashboard.pbix`
- Update the data source path to your local `churn_model.xlsx`
- Click **Refresh**

---

## Limitations & Future Work

### Current Limitations
- This is **churn analysis, not true churn prediction** — patients are labelled based on past behaviour, not predicted in advance
- The 180-day churn threshold was manually chosen and would need domain expert validation in a real project
- The dataset is synthetic — real hospital data would include richer signals like diagnosis codes, lab values and appointment no-shows

### Future Improvements

| Enhancement | Description |
|---|---|
| Machine Learning | Add Python (scikit-learn) Random Forest or Logistic Regression to predict future churn probability |
| Real Data | Integrate with MIMIC-III or a live hospital EMR system |
| Automated Refresh | Schedule PostgreSQL → Power BI pipeline with automatic data refresh |
| Patient Outreach | Trigger SMS/email alerts directly from Power BI for Critical segment patients |
| Survival Analysis | Use Kaplan-Meier curves to model time-to-churn distribution |

---

## Author

Built as a portfolio project demonstrating end-to-end data analytics skills across SQL, Excel and Business Intelligence.

---

## License

This project uses a synthetic dataset generated for educational purposes. No real patient data was used.
