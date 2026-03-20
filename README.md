# Patient-Churn-Analysis
Built a patient churn analysis system using RFM scoring in PostgreSQL and Excel, with an interactive Power BI dashboard to identify and segment at-risk patients


# 🏥 Hospital Patient Churn Analysis & Risk Segmentation
 
> An end-to-end data analytics project to identify and segment patients at risk of not returning to a hospital, using PostgreSQL, Excel, and Power BI.
 
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
| PostgreSQL | 15+ | Data storage, SQL queries, feature engineering |
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
| `Patient ID` | Unique identifier per patient |
| `Name` | Patient name |
| `Age` | Age at time of admission |
| `Gender` | Male / Female |
| `Blood Type` | A+, A-, B+, B-, O+, O-, AB+, AB- |
| `Medical Condition` | Primary diagnosis (e.g. Diabetes, Hypertension) |
| `Date of Admission` | Date patient was admitted |
| `Doctor` | Treating doctor |
| `Hospital` | Hospital name |
| `Insurance Provider` | Patient's insurance company |
| `Billing Amount` | Total bill for the admission (INR) |
| `Room Number` | Assigned room |
| `Admission Type` | Elective / Emergency / Urgent |
| `Discharge Date` | Date patient was discharged |
| `Medication` | Primary medication prescribed |
| `Test Results` | Normal / Abnormal / Inconclusive |
 
---
 
## Project Architecture
 
```
Raw CSV (50k rows)
       │
       ▼
┌─────────────────┐
│   PostgreSQL    │  ← CREATE TABLE, BULK IMPORT
│                 │
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
│   Dashboard     │  ← Conditional formatting
└─────────────────┘
```
 
---
 
## Phase 1 — PostgreSQL: Data Engineering
 
### Step 1: Create Table
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
 
### Step 2: Build Patient-Level Visit History
```sql
CREATE TABLE patient_visits AS
SELECT
    name, age, gender, insurance_provider, medical_condition,
    COUNT(*)                                                        AS total_admissions,
    MIN(date_of_admission)                                          AS first_admission,
    MAX(date_of_admission)                                          AS last_admission,
    MAX(discharge_date)                                             AS last_discharge,
    ((SELECT MAX(discharge_date) FROM healthcare) - MAX(discharge_date)) AS days_since_last_visit,
    SUM(billing_amount)                                             AS total_billing,
    AVG(billing_amount)                                             AS avg_billing,
    SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END)  AS emergency_count,
    SUM(CASE WHEN test_results = 'Abnormal'    THEN 1 ELSE 0 END)  AS abnormal_tests
FROM healthcare
GROUP BY name, age, gender, insurance_provider, medical_condition;
```
 
### Step 3: Apply Churn Definition
```sql
CREATE TABLE churn_flagged AS
SELECT *,
    CASE
        WHEN last_discharge < (DATE '2024-06-06' - INTERVAL '180 days')
        THEN 1 ELSE 0
    END AS is_churned
FROM patient_visits;
```
 
### Step 4: RFM Scoring
```sql
CREATE TABLE rfm_scored AS
SELECT *,
    CASE
        WHEN days_since_last_visit <= 180  THEN 5
        WHEN days_since_last_visit <= 365  THEN 4
        WHEN days_since_last_visit <= 730  THEN 3
        WHEN days_since_last_visit <= 1095 THEN 2
        ELSE 1
    END AS recency_score,
    CASE
        WHEN total_admissions >= 8 THEN 5
        WHEN total_admissions >= 5 THEN 4
        WHEN total_admissions >= 3 THEN 3
        WHEN total_admissions >= 1 THEN 2
        ELSE 1
    END AS frequency_score,
    CASE
        WHEN total_billing >= 40000 THEN 5
        WHEN total_billing >= 20000 THEN 4
        WHEN total_billing >= 10000 THEN 3
        WHEN total_billing >= 5000  THEN 2
        ELSE 1
    END AS monetary_score
FROM churn_flagged;
```
 
---
 
## Phase 2 — Excel: RFM Scoring & Segmentation
 
After exporting `rfm_scored` to CSV, two columns were added in Excel:
 
### Risk Segment Formula
```excel
=IF(R2>=4.0,"Low Risk",IF(R2>=3.0,"Medium Risk",IF(R2>=2.0,"High Risk","Critical")))
```
 
### Churn Probability Formula
```excel
=IF(S2="Critical",95,IF(S2="High Risk",70,IF(S2="Medium Risk",40,10)))
```
 
A **Pivot Table** was created for validation:
- Rows: `Risk Segment`
- Columns: `Insurance Provider`
- Values: Count of patients, Average churn score, Sum of billing
 
---
 
## Phase 3 — Power BI: Dashboard & Visuals
 
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
 
### Dashboard Pages
 
| Page | Contents |
|---|---|
| Executive Overview | KPI cards, churn trend line, churn by medical condition |
| Risk Segments | Donut chart, billing by segment, risk by insurer matrix |
| At-Risk Patient List | Sortable table with conditional formatting by risk color |
| Filters | Slicers for insurance, condition, gender, admission type |
 
### Conditional Formatting (Risk Colors)
 
```dax
Risk Color =
SWITCH(
    SELECTEDVALUE(churn_model[Risk Segment]),
    "Critical",     "#FF4444",
    "High Risk",    "#FF8C00",
    "Medium Risk",  "#FFD700",
    "Low Risk",     "#00C853",
    "#FFFFFF"
)
```
 
---
 
## Churn Definition
 
A patient is classified as **churned** if their last discharge date was more than **180 days before the dataset's end date** (2024-06-06).
 
```
Churn cutoff = 2024-06-06 − 180 days = 2023-12-08
 
Patient last discharged BEFORE 2023-12-08 → is_churned = 1
Patient last discharged AFTER  2023-12-08 → is_churned = 0
```
 
> **Note:** `CURRENT_DATE` was intentionally avoided as the dataset ends in 2024. Using today's date would mark every patient as churned.
 
---
 
## RFM Model Explained
 
RFM is a proven customer analytics framework adapted here for healthcare:
 
| Dimension | Definition | Weight | Rationale |
|---|---|---|---|
| **Recency** | Days since last discharge | 40% | Most important — recent patients are most re-engageable |
| **Frequency** | Total number of admissions | 35% | Frequent patients show hospital loyalty |
| **Monetary** | Total billing amount | 25% | High-value patients worth prioritising for retention |
 
### Scoring Thresholds
 
**Recency Score**
 
| Days Since Last Visit | Score |
|---|---|
| ≤ 180 days | 5 |
| ≤ 365 days | 4 |
| ≤ 730 days | 3 |
| ≤ 1095 days | 2 |
| > 1095 days | 1 |
 
**Frequency Score**
 
| Total Admissions | Score |
|---|---|
| 8+ | 5 |
| 5–7 | 4 |
| 3–4 | 3 |
| 1–2 | 2 |
| 0 | 1 |
 
**Monetary Score**
 
| Total Billing (INR) | Score |
|---|---|
| ≥ 40,000 | 5 |
| ≥ 20,000 | 4 |
| ≥ 10,000 | 3 |
| ≥ 5,000 | 2 |
| < 5,000 | 1 |
 
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
| 🔴 Critical | < 2.0 | 95% | Immediate SMS/call re-engagement |
 
---
 
## Key Insights
 
- Patients with **Emergency admissions** had higher churn rates — likely discharged and not followed up
- **Chronic condition patients** (Diabetes, Hypertension) who churned represent the highest revenue risk
- Churn was highest among **self-pay patients** compared to insured patients
- Patients with **Abnormal test results** who churned are a clinical concern beyond just revenue
 
---
 
## Project Structure
 
```
hospital-churn-prediction/
│
├── data/
│   └── hospital_churn_data.csv       ← 50,000 row synthetic dataset
│
├── sql/
│   ├── 1_create_table.sql            ← Healthcare table schema
│   ├── 2_patient_visits.sql          ← Patient-level aggregation
│   ├── 3_churn_flagged.sql           ← Churn labelling
│   └── 4_rfm_scored.sql              ← RFM scoring + final export query
│
├── excel/
│   └── churn_model.xlsx              ← Risk segment + probability columns + pivot
│
├── powerbi/
│   └── hospital_churn_dashboard.pbix ← Full Power BI dashboard
│
└── README.md
```
 
---
 
## How to Run
 
### 1. Set up PostgreSQL
- Install PostgreSQL and pgAdmin
- Create a new database called `hospital_churn`
 
### 2. Load the data
- Open pgAdmin → right-click `healthcare` table → Import/Export Data
- Import `data/hospital_churn_data.csv` with Header ON, Delimiter `,`
 
### 3. Run SQL scripts in order
```
sql/1_create_table.sql
sql/2_patient_visits.sql
sql/3_churn_flagged.sql
sql/4_rfm_scored.sql
```
 
### 4. Export to Excel
- Run the final SELECT query in `4_rfm_scored.sql`
- Right-click results → Download as CSV
- Open in Excel, add Risk Segment and Churn Probability columns
- Save as `churn_model.xlsx`
 
### 5. Open Power BI
- Open `powerbi/hospital_churn_dashboard.pbix`
- Update data source path to point to your `churn_model.xlsx`
- Refresh data
 
---
 
## Limitations & Future Work
 
### Current Limitations
- This is **churn analysis**, not true churn **prediction** — patients are labelled after the fact based on historical behaviour, not predicted in advance
- The 180-day churn threshold was manually chosen — in a real project this would be validated with domain experts
- The dataset is synthetic — real hospital data would have richer signals (diagnosis codes, lab values, appointment no-shows)
 
### Future Improvements
 
| Enhancement | Description |
|---|---|
| Machine Learning | Add Python (scikit-learn) Random Forest model to predict future churn probability |
| Real Data | Integrate with MIMIC-III or a live hospital EMR system |
| Automated Refresh | Schedule PostgreSQL → Power BI refresh pipeline |
| Patient Outreach | Connect Power BI alerts to an SMS/email notification system |
| Survival Analysis | Use Kaplan-Meier curves to model time-to-churn |
 
---
 
## Author
 
Built as a portfolio project demonstrating end-to-end data analytics skills across SQL, Excel, and Business Intelligence.
 
---
 
## License
 
This project uses a synthetic dataset generated for educational purposes. No real patient data was used.
