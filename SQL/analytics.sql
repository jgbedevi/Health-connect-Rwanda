-- =====================================================================
-- HealthConnect Rwanda | Data Analytics track | Week 6
-- Script 02: analytical views for the SQL queries and Power BI
-- Prerequisite: 01_nettoyage_validation.sql has been run
-- In Power BI, import only the views of the analytics schema
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS analytics;

-- One row per village (prevents patients from being duplicated by the join)
DROP VIEW IF EXISTS analytics.dim_geography CASCADE;
CREATE VIEW analytics.dim_geography AS
SELECT DISTINCT ON (village_id) village_id, village_name, sector_name, district_name, province_name
FROM clean.geography
ORDER BY village_id;

DROP VIEW IF EXISTS analytics.v_patients CASCADE;
CREATE VIEW analytics.v_patients AS
SELECT p.*, g.village_name, g.sector_name, g.district_name, g.province_name
FROM clean.patients p
LEFT JOIN analytics.dim_geography g ON g.village_id = p.village_id;

DROP VIEW IF EXISTS analytics.v_staff CASCADE;
CREATE VIEW analytics.v_staff AS
SELECT s.*, d.department_name
FROM clean.staff s
LEFT JOIN clean.departments d ON d.department_id = s.department_id;

DROP VIEW IF EXISTS analytics.v_appointments CASCADE;
CREATE VIEW analytics.v_appointments AS
SELECT a.appointment_id, a.appointment_date, a.visit_type,
       a.facility_id, a.department_id, d.department_name,
       a.doctor_id, (st.first_name || ' ' || st.last_name) AS doctor_name,
       a.patient_id, p.gender, p.age, p.age_group, p.is_insured, p.has_chronic_disease,
       p.district_name, p.province_name,
       a.patient_valid, a.doctor_valid, a.department_valid, a.date_valid
FROM clean.appointments a
LEFT JOIN clean.departments d ON d.department_id = a.department_id
LEFT JOIN clean.staff st ON st.staff_type = 'Doctor' AND st.staff_id = a.doctor_id
LEFT JOIN analytics.v_patients p ON p.patient_id = a.patient_id;

-- Billing: facility, department, date and province are only filled for the
-- bills linked to an appointment (has_appointment = true)
DROP VIEW IF EXISTS analytics.v_billing CASCADE;
CREATE VIEW analytics.v_billing AS
SELECT b.billing_id, b.appointment_id, b.amount, b.status, b.amount_paid, b.balance_due,
       -- Outstanding is derived from the payments actually recorded, not from the Status label
       -- (every Pending bill has a payment, and some Paid bills still have a balance)
       CASE WHEN b.amount_valid THEN GREATEST(b.balance_due, 0) ELSE 0 END AS outstanding_amount,
       b.amount_valid, b.has_appointment,
       a.appointment_date, date_trunc('month', a.appointment_date)::date AS appointment_month,
       a.facility_id, a.department_id, a.department_name, a.patient_id, a.province_name, a.visit_type
FROM clean.billing b
LEFT JOIN analytics.v_appointments a ON a.appointment_id = b.appointment_id;

DROP VIEW IF EXISTS analytics.v_claims CASCADE;
CREATE VIEW analytics.v_claims AS
SELECT c.claim_id, c.billing_id, c.provider, c.claim_amount, c.status,
       b.amount AS billed_amount, b.facility_id, b.department_name, b.appointment_month
FROM clean.insurance_claims c
LEFT JOIN analytics.v_billing b ON b.billing_id = c.billing_id;

DROP VIEW IF EXISTS analytics.v_diagnoses CASCADE;
CREATE VIEW analytics.v_diagnoses AS
SELECT g.diagnosis_id, g.appointment_id, g.diagnosis, g.severity, g.has_appointment,
       a.appointment_date, date_trunc('month', a.appointment_date)::date AS appointment_month,
       a.facility_id, a.department_id, a.department_name, a.patient_id, a.province_name
FROM clean.diagnoses g
LEFT JOIN analytics.v_appointments a ON a.appointment_id = g.appointment_id;

DROP VIEW IF EXISTS analytics.v_feedback CASCADE;
CREATE VIEW analytics.v_feedback AS
SELECT f.feedback_id, f.appointment_id, f.rating, f.rating_valid, f.comment, f.has_appointment,
       a.appointment_date, date_trunc('month', a.appointment_date)::date AS appointment_month,
       a.facility_id, a.department_id, a.department_name
FROM clean.patient_feedback f
LEFT JOIN analytics.v_appointments a ON a.appointment_id = f.appointment_id;

-- Dimensions for the Power BI model
-- Facility and department are independent in the source data (see dq_report), so no relationship between them
DROP VIEW IF EXISTS analytics.dim_department CASCADE;
CREATE VIEW analytics.dim_department AS
SELECT department_id, department_name FROM clean.departments;

DROP VIEW IF EXISTS analytics.dim_facility CASCADE;
CREATE VIEW analytics.dim_facility AS
SELECT facility_id FROM (
  SELECT facility_id FROM clean.departments
  UNION SELECT facility_id FROM clean.appointments
  UNION SELECT facility_id FROM clean.staff
  UNION SELECT facility_id FROM clean.rooms
  UNION SELECT facility_id FROM clean.equipment) f
WHERE facility_id IS NOT NULL;

-- Beds with their room, department and facility
DROP VIEW IF EXISTS analytics.v_beds CASCADE;
CREATE VIEW analytics.v_beds AS
SELECT b.bed_id, b.room_id, b.status, r.room_name, r.department_id, r.facility_id
FROM clean.beds b LEFT JOIN clean.rooms r ON r.room_id = b.room_id;

DROP VIEW IF EXISTS analytics.v_equipment CASCADE;
CREATE VIEW analytics.v_equipment AS
SELECT equipment_id, equipment_name, department_id, facility_id FROM clean.equipment;

-- Data coverage indicator: to be displayed in the dashboard
DROP VIEW IF EXISTS analytics.v_data_coverage CASCADE;
CREATE VIEW analytics.v_data_coverage AS
SELECT 'Factures'      AS table_name, COUNT(*) AS total, COUNT(*) FILTER (WHERE has_appointment) AS reliees_rdv,
       round(100.0 * COUNT(*) FILTER (WHERE has_appointment) / COUNT(*), 1) AS pct_reliees FROM clean.billing
UNION ALL SELECT 'Diagnostics', COUNT(*), COUNT(*) FILTER (WHERE has_appointment),
       round(100.0 * COUNT(*) FILTER (WHERE has_appointment) / COUNT(*), 1) FROM clean.diagnoses
UNION ALL SELECT 'Avis patients', COUNT(*), COUNT(*) FILTER (WHERE has_appointment),
       round(100.0 * COUNT(*) FILTER (WHERE has_appointment) / COUNT(*), 1) FROM clean.patient_feedback;

SELECT * FROM analytics.v_data_coverage;