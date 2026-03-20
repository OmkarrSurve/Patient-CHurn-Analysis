CREATE TABLE healthcare (
    patient_id        INT,
    name              VARCHAR(100),
    age               INT,
    gender            VARCHAR(10),
    blood_type        VARCHAR(5),
    medical_condition VARCHAR(100),
    date_of_admission DATE,
    doctor            VARCHAR(100),
    hospital          VARCHAR(100),
    insurance_provider VARCHAR(50),
    billing_amount    NUMERIC(10,2),
    room_number       INT,
    admission_type    VARCHAR(20),
    discharge_date    DATE,
    medication        VARCHAR(100),
    test_results      VARCHAR(20)
);

SELECT * FROM healthcare;

--Build patient-level visit history
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

SELECT * FROM patient_visits


--cREATE CHURN TABLE
CREATE TABLE churn_flagged AS
SELECT *,
    CASE 
        WHEN last_discharge < (
            (SELECT MAX(discharge_date) FROM healthcare) - INTERVAL '180 days'
        )
        THEN 1 ELSE 0 
    END AS is_churned
FROM patient_visits;

SELECT * FROM churn_flagged;

CREATE TABLE rfm_scored AS
SELECT *,
    CASE
        WHEN days_since_last_visit <= 180  THEN 5   -- last 6 months
        WHEN days_since_last_visit <= 365  THEN 4   -- last 1 year
        WHEN days_since_last_visit <= 730  THEN 3   -- last 2 years
        WHEN days_since_last_visit <= 1095 THEN 2   -- last 3 years
        ELSE 1                                       -- 3+ years ago
    END AS recency_score,
    CASE
        WHEN total_admissions >= 9 THEN 5
        WHEN total_admissions >= 7 THEN 4
        WHEN total_admissions >= 4 THEN 3
        WHEN total_admissions >= 2 THEN 2
        ELSE 1
    END AS frequency_score,
    CASE
        WHEN total_billing >= 150000 THEN 5
        WHEN total_billing >= 100000 THEN 4
        WHEN total_billing >= 70000 THEN 3
        WHEN total_billing >= 30000  THEN 2
        ELSE 1
    END AS monetary_score
FROM churn_flagged;

SELECT * FROM rfm_scored;

SELECT
    name, age, gender, insurance_provider, medical_condition,
    total_admissions, first_admission, last_admission, days_since_last_visit,
    ROUND(total_billing::NUMERIC, 2)  AS total_billing,
    ROUND(avg_billing::NUMERIC, 2)    AS avg_billing,
    emergency_count, abnormal_tests,
    is_churned, recency_score, frequency_score, monetary_score,
    ROUND(
        ((recency_score * 0.40) + (frequency_score * 0.35) + (monetary_score * 0.25))::NUMERIC
    , 2) AS churn_score
FROM rfm_scored
ORDER BY churn_score asc;

