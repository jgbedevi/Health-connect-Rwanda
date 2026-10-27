-- =====================================================================
-- HealthConnect Rwanda | Data Analytics track | Week 6
-- Script 03: the 40 SQL queries from the assignment
-- Prerequisite: scripts 01 and 02 have been run
--
-- DATA LIMITATIONS (read before interpreting the results)
--  * hc_clinical_transactions only holds 5,000 appointments
--    (APT000001 to APT005000), while billing, diagnoses and feedback
--    go up to APT060000. Analyses by facility, department, province or
--    date therefore cover only about 8% of the bills
--    (see analytics.v_data_coverage).
--  * There are no admissions, laboratory, prescription or referral
--    tables: queries 22 to 24 and 26 to 28 cannot be answered.
--  * There is no facility master table: hospitals are identified by
--    their FacilityID.
--  * The Phone column is corrupted at the source (10 distinct values).
-- =====================================================================

-- ============================ PATIENT ANALYSIS ========================

-- 1. Retrieve all registered patients
SELECT * FROM clean.patients ORDER BY patient_id;

-- 2. Count patients by gender
SELECT gender, COUNT(*) AS patients,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM clean.patients GROUP BY gender ORDER BY patients DESC;

-- 3. Count patients by province (province of residence)
SELECT COALESCE(province_name, 'Unknown') AS province, COUNT(*) AS patients,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM analytics.v_patients GROUP BY 1 ORDER BY patients DESC;

-- 4. Identify patients above 65 years
SELECT patient_id, first_name, last_name, gender, age
FROM clean.patients WHERE age > 65 ORDER BY age DESC, patient_id;

-- 5. Find patients with chronic diseases
SELECT patient_id, first_name, last_name, age, chronic_condition
FROM clean.patients WHERE has_chronic_disease ORDER BY chronic_condition, patient_id;

-- 5b. Breakdown by chronic condition
SELECT chronic_condition, COUNT(*) AS patients
FROM clean.patients WHERE has_chronic_disease GROUP BY 1 ORDER BY patients DESC;

-- 6. Retrieve patients covered by insurance (InsuranceID filled in)
SELECT COUNT(*) FILTER (WHERE is_insured) AS insured_patients,
       COUNT(*) AS total_patients,
       round(100.0 * COUNT(*) FILTER (WHERE is_insured) / COUNT(*), 1) AS coverage_rate_pct
FROM clean.patients;

-- 6b. Breakdown by insurance ID
SELECT insurance_id, COUNT(*) AS patients FROM clean.patients
WHERE is_insured GROUP BY 1 ORDER BY patients DESC;

-- 7. Count patients by blood group
SELECT blood_group, COUNT(*) AS patients FROM clean.patients
GROUP BY 1 ORDER BY patients DESC;

-- 8. List the 5 youngest and the 5 oldest patients
(SELECT 'Youngest' AS category, patient_id, first_name, last_name, age
 FROM clean.patients WHERE age IS NOT NULL ORDER BY age ASC, patient_id LIMIT 5)
UNION ALL
(SELECT 'Oldest', patient_id, first_name, last_name, age
 FROM clean.patients WHERE age IS NOT NULL ORDER BY age DESC, patient_id LIMIT 5);

-- 9. Identify duplicate phone numbers
-- 9a. Diagnosis: the column is unusable (very few distinct values)
SELECT COUNT(*) AS patients, COUNT(DISTINCT "Phone") AS distinct_phone_numbers
FROM raw.hc_patients;
-- 9b. Reliable alternative: duplicate patient records (first name + last name + date of birth)
SELECT first_name, last_name, date_of_birth, COUNT(*) AS occurrences
FROM clean.patients
GROUP BY 1, 2, 3 HAVING COUNT(*) > 1 ORDER BY occurrences DESC LIMIT 50;

-- 10. Calculate average patient age
SELECT round(AVG(age), 1) AS average_age, MIN(age) AS min_age, MAX(age) AS max_age
FROM clean.patients;

-- ========================= APPOINTMENT ANALYSIS =======================
-- (base: the 5,000 appointments available)

-- 11. Count appointments by month
SELECT date_trunc('month', appointment_date)::date AS month, COUNT(*) AS appointments
FROM clean.appointments WHERE date_valid GROUP BY 1 ORDER BY 1;

-- 12. Identify busiest hospitals
SELECT facility_id, COUNT(*) AS appointments,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM clean.appointments GROUP BY 1 ORDER BY appointments DESC;

-- 13. Find busiest departments
SELECT COALESCE(department_name, department_id) AS department, facility_id, COUNT(*) AS appointments
FROM analytics.v_appointments GROUP BY 1, 2 ORDER BY appointments DESC LIMIT 20;

-- 14. Find doctors with the highest workload
SELECT doctor_id, doctor_name, department_name, COUNT(*) AS appointments
FROM analytics.v_appointments GROUP BY 1, 2, 3 ORDER BY appointments DESC LIMIT 20;

-- 15. Identify referral patterns
-- VisitType has no "Referral" value, so we show the distribution of visit types instead.
SELECT visit_type, COUNT(*) AS appointments,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM clean.appointments GROUP BY 1 ORDER BY appointments DESC;

-- 16. Count emergency appointments
SELECT COUNT(*) FILTER (WHERE visit_type = 'Emergency') AS emergency_appointments,
       COUNT(*) AS total_appointments,
       round(100.0 * COUNT(*) FILTER (WHERE visit_type = 'Emergency') / COUNT(*), 1) AS emergency_pct
FROM clean.appointments;

-- 17. Calculate average appointments per doctor
SELECT COUNT(*) AS appointments,
       COUNT(DISTINCT doctor_id) FILTER (WHERE doctor_valid) AS active_doctors,
       round(COUNT(*)::numeric / NULLIF(COUNT(DISTINCT doctor_id) FILTER (WHERE doctor_valid), 0), 1) AS avg_per_active_doctor,
       (SELECT COUNT(*) FROM clean.staff WHERE staff_type = 'Doctor') AS registered_doctors,
       round(COUNT(*)::numeric / NULLIF((SELECT COUNT(*) FROM clean.staff WHERE staff_type = 'Doctor'), 0), 1) AS avg_per_registered_doctor
FROM clean.appointments;

-- 18. Retrieve appointments by province (province of residence of the patient)
SELECT COALESCE(province_name, 'Unknown') AS province, COUNT(*) AS appointments
FROM analytics.v_appointments GROUP BY 1 ORDER BY appointments DESC;

-- 19. Identify facilities with the highest patient volume (distinct patients)
SELECT facility_id, COUNT(DISTINCT patient_id) AS distinct_patients, COUNT(*) AS appointments
FROM clean.appointments WHERE patient_valid
GROUP BY 1 ORDER BY distinct_patients DESC;

-- 20. Find peak consultation periods (dates carry no time of day, so we use weekday and month)
-- 20a. By day of the week
SELECT to_char(appointment_date, 'ID') AS weekday_number, trim(to_char(appointment_date, 'Day')) AS weekday, COUNT(*) AS appointments
FROM clean.appointments WHERE date_valid GROUP BY 1, 2 ORDER BY 1;
-- 20b. By month, consultations only
SELECT date_trunc('month', appointment_date)::date AS month, COUNT(*) AS consultations
FROM clean.appointments WHERE date_valid AND visit_type = 'Consultation' GROUP BY 1 ORDER BY consultations DESC;

-- ============================ CLINICAL ANALYSIS =======================

-- 21. Top diagnoses (all 60,000 diagnosis records)
SELECT diagnosis, COUNT(*) AS cases,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM clean.diagnoses GROUP BY 1 ORDER BY cases DESC LIMIT 20;

-- 22. Most requested laboratory tests
SELECT 'Not possible: the dataset has no laboratory test table' AS note;

-- 23. Most prescribed medications
SELECT 'Not possible: the dataset has no prescription table' AS note;

-- 24. Average admission duration
SELECT 'Not possible: the dataset has no admissions table' AS note;

-- 25. Disease severity distribution
SELECT severity, COUNT(*) AS cases,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM clean.diagnoses GROUP BY 1 ORDER BY cases DESC;

-- 26. Laboratory test utilization
SELECT 'Not possible: the dataset has no laboratory test table' AS note;

-- 27. Prescription trends
SELECT 'Not possible: the dataset has no prescription table' AS note;

-- 28. Referral destinations
SELECT 'Not possible: the dataset has no referral table' AS note;

-- 29. Admission rate by diagnosis
-- Proxy: share of "Severe" cases per diagnosis (there is no admissions table)
SELECT diagnosis, COUNT(*) AS cases,
       COUNT(*) FILTER (WHERE severity = 'Severe') AS severe_cases,
       round(100.0 * COUNT(*) FILTER (WHERE severity = 'Severe') / COUNT(*), 1) AS severe_pct
FROM clean.diagnoses GROUP BY 1 ORDER BY severe_pct DESC, cases DESC LIMIT 20;

-- 30. Clinical workload by department (diagnoses linked to an appointment)
SELECT COALESCE(department_name, department_id) AS department, facility_id,
       COUNT(*) AS diagnoses,
       COUNT(*) FILTER (WHERE severity = 'Severe') AS severe_cases
FROM analytics.v_diagnoses WHERE has_appointment
GROUP BY 1, 2 ORDER BY diagnoses DESC LIMIT 20;

-- =========================== FINANCIAL ANALYSIS =======================
-- Revenue = billed amount (clean.billing.amount, valid amounts only).
-- Collected = sum of payments (clean.payments).
-- By facility, department or month: only bills linked to an appointment.

-- 31. Revenue by facility
SELECT facility_id, COUNT(*) AS bills,
       SUM(amount) AS billed, SUM(amount_paid) AS collected,
       round(100.0 * SUM(amount_paid) / NULLIF(SUM(amount), 0), 1) AS collection_rate_pct
FROM analytics.v_billing WHERE has_appointment AND amount_valid
GROUP BY 1 ORDER BY billed DESC;

-- 32. Revenue by department
SELECT COALESCE(department_name, department_id) AS department,
       COUNT(*) AS bills, SUM(amount) AS billed, SUM(amount_paid) AS collected
FROM analytics.v_billing WHERE has_appointment AND amount_valid
GROUP BY 1 ORDER BY billed DESC;

-- 33. Revenue by service
-- Bills do not reference a service, so the analysis is done at department level,
-- alongside the list of services each department offers.
SELECT d.department_name, SUM(v.amount) AS billed,
       (SELECT string_agg(s.service_name, ', ' ORDER BY s.service_name)
        FROM clean.services s WHERE s.department_id = v.department_id) AS department_services
FROM analytics.v_billing v
JOIN clean.departments d ON d.department_id = v.department_id
WHERE v.has_appointment AND v.amount_valid
GROUP BY d.department_name, v.department_id ORDER BY billed DESC;

-- 34. Insurance claims by provider (all claims)
SELECT provider, COUNT(*) AS claims, SUM(claim_amount) AS claimed_amount,
       COUNT(*) FILTER (WHERE status = 'Approved') AS approved,
       round(100.0 * COUNT(*) FILTER (WHERE status = 'Approved') / COUNT(*), 1) AS approval_rate_pct
FROM clean.insurance_claims GROUP BY 1 ORDER BY claimed_amount DESC;

-- 35. Outstanding payments (all bills)
SELECT status, COUNT(*) AS bills,
       SUM(amount) AS billed, SUM(amount_paid) AS collected,
       SUM(GREATEST(balance_due, 0)) AS outstanding
FROM clean.billing WHERE amount_valid GROUP BY 1 ORDER BY outstanding DESC;

-- 35b. Outstanding amount computed from recorded payments (billed minus collected), whatever the Status label says
SELECT COUNT(*) FILTER (WHERE balance_due > 0) AS bills_with_balance,
       SUM(GREATEST(balance_due, 0)) AS total_outstanding,
       round(100.0 * SUM(GREATEST(balance_due, 0)) / SUM(amount), 1) AS outstanding_pct_of_billed
FROM clean.billing WHERE amount_valid;

-- 36. Average billing amount
SELECT round(AVG(amount), 0) AS average, percentile_cont(0.5) WITHIN GROUP (ORDER BY amount) AS median,
       MIN(amount) AS minimum, MAX(amount) AS maximum
FROM clean.billing WHERE amount_valid;

-- 37. Monthly revenue trend
-- 37a. From bills linked to a dated appointment
SELECT appointment_month AS month, SUM(amount) AS billed, SUM(amount_paid) AS collected
FROM analytics.v_billing WHERE has_appointment AND amount_valid AND appointment_month IS NOT NULL
GROUP BY 1 ORDER BY 1;
-- 37b. Revenue summary table provided with the dataset (does not reconcile with billing, to be flagged)
SELECT month, revenue AS summary_revenue, appointments_declared
FROM clean.revenue_summary ORDER BY 1;

-- 38. Payment methods
SELECT method, COUNT(*) AS payments, SUM(amount_paid) AS amount,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_payments
FROM clean.payments GROUP BY 1 ORDER BY amount DESC;

-- 39. Top revenue-generating hospitals (top 10)
SELECT facility_id, SUM(amount) AS billed, SUM(amount_paid) AS collected
FROM analytics.v_billing WHERE has_appointment AND amount_valid
GROUP BY 1 ORDER BY billed DESC LIMIT 10;

-- 40. Financial performance ranking of facilities
-- Global rank = combined rank on revenue and on collection rate
WITH f AS (
  SELECT facility_id, COUNT(*) AS bills, SUM(amount) AS billed, SUM(amount_paid) AS collected,
         round(100.0 * SUM(amount_paid) / NULLIF(SUM(amount), 0), 1) AS collection_rate_pct,
         round(AVG(amount), 0) AS average_bill
  FROM analytics.v_billing WHERE has_appointment AND amount_valid GROUP BY 1),
r AS (
  SELECT f.*,
         RANK() OVER (ORDER BY billed DESC) AS revenue_rank,
         RANK() OVER (ORDER BY collection_rate_pct DESC) AS collection_rank
  FROM f)
SELECT facility_id, bills, billed, collected, collection_rate_pct, average_bill,
       revenue_rank, collection_rank,
       RANK() OVER (ORDER BY revenue_rank + collection_rank) AS overall_rank
FROM r ORDER BY overall_rank, facility_id;