-- =====================================================================
-- HealthConnect Rwanda | Data Analytics track | Week 6
-- Script 01: data cleaning, validation and data quality report
-- Source: schema raw (raw data, never modified)
-- Target: schema clean (cleaned data) + clean.dq_report
-- Execution: run the whole file, top to bottom
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS clean;

-- ---------------------------------------------------------------------
-- 0. Helper functions (safe conversions, bad values become NULL instead of failing)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clean.norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN upper(btrim(t)) IN ('', 'NULL', 'NAN', 'NONE', 'N/A') THEN NULL
              ELSE btrim(t) END
$$;

CREATE OR REPLACE FUNCTION clean.safe_num(t text) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN btrim(t) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(t)::numeric END
$$;

CREATE OR REPLACE FUNCTION clean.safe_date(t text) RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  t := btrim(t);
  IF t ~ '^\d{4}-\d{2}-\d{2}' THEN
    RETURN left(t, 10)::date;
  ELSIF t ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
    RETURN to_date(t, 'MM/DD/YYYY');   -- US format observed in the source: 1/1/2007
  END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN
  RETURN NULL;
END
$$;

-- ---------------------------------------------------------------------
-- 1. Reference tables: geography, departments, staff, infrastructure
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.geography CASCADE;
CREATE TABLE clean.geography AS
SELECT clean.norm(v."VillageID") AS village_id, v."VillageName" AS village_name,
       s."SectorName"   AS sector_name,
       d."DistrictName" AS district_name,
       p."ProvinceName" AS province_name
FROM raw.hc_villages v
LEFT JOIN raw.hc_sectors   s ON s."SectorID"   = v."SectorID"
LEFT JOIN raw.hc_districts d ON d."DistrictID" = s."DistrictID"
LEFT JOIN raw.hc_provinces p ON p."ProvinceID" = d."ProvinceID";

DROP TABLE IF EXISTS clean.departments CASCADE;
CREATE TABLE clean.departments AS
SELECT department_id, department_name, facility_id FROM (
  SELECT clean.norm("DepartmentID") AS department_id,
         initcap(clean.norm("DepartmentName")) AS department_name,
         clean.norm("FacilityID") AS facility_id,
         row_number() OVER (PARTITION BY clean.norm("DepartmentID") ORDER BY ctid) AS rn
  FROM raw.hc_departments) t
WHERE rn = 1 AND department_id IS NOT NULL;

DROP TABLE IF EXISTS clean.staff CASCADE;
CREATE TABLE clean.staff AS
SELECT staff_type, staff_id, first_name, last_name, role, department, specialty,
       facility_id, department_id, years_experience, status
FROM (
  SELECT s.staff_type,
         clean.norm(s."StaffID") AS staff_id,
         initcap(clean.norm(s."FirstName")) AS first_name,
         initcap(clean.norm(s."LastName"))  AS last_name,
         clean.norm(s."Role") AS role,
         clean.norm(s."Department") AS department,
         clean.norm(s."Specialty") AS specialty,
         clean.norm(s."FacilityID") AS facility_id,
         clean.norm(s."DepartmentID") AS department_id,
         clean.safe_num(s."YearsExperience") AS years_experience,
         initcap(clean.norm(s."Status")) AS status,
         row_number() OVER (PARTITION BY s.staff_type, clean.norm(s."StaffID")
                            ORDER BY s."FirstName", s."LastName") AS rn
  FROM (
    SELECT 'Doctor' AS staff_type, * FROM raw.hc_doctor
    UNION ALL SELECT 'Nurse', *                FROM raw.hc_nurse
    UNION ALL SELECT 'Pharmacist', *           FROM raw.pharmacist
    UNION ALL SELECT 'Laboratory Scientist', * FROM raw.laboratory_scientist
    UNION ALL SELECT 'Radiographer', *         FROM raw.hc_radiographer
    UNION ALL SELECT 'Administrative', *       FROM raw.hc_administrative_staff
  ) s) t
WHERE rn = 1 AND staff_id IS NOT NULL;

DROP TABLE IF EXISTS clean.rooms CASCADE;
CREATE TABLE clean.rooms AS
SELECT DISTINCT clean.norm("RoomID") AS room_id, clean.norm("DepartmentID") AS department_id,
       clean.norm("FacilityID") AS facility_id, clean.norm("RoomName") AS room_name
FROM raw.hc_rooms WHERE clean.norm("RoomID") IS NOT NULL;

DROP TABLE IF EXISTS clean.beds CASCADE;
CREATE TABLE clean.beds AS
SELECT DISTINCT clean.norm("BedID") AS bed_id, clean.norm("RoomID") AS room_id,
       initcap(clean.norm("Status")) AS status
FROM raw.hc_beds WHERE clean.norm("BedID") IS NOT NULL;

DROP TABLE IF EXISTS clean.equipment CASCADE;
CREATE TABLE clean.equipment AS
SELECT DISTINCT clean.norm("EquipmentID") AS equipment_id,
       clean.norm("EquipmentName") AS equipment_name,
       clean.norm("DepartmentID") AS department_id, clean.norm("FacilityID") AS facility_id
FROM raw.hc_medical_equipment WHERE clean.norm("EquipmentID") IS NOT NULL;

DROP TABLE IF EXISTS clean.services CASCADE;
CREATE TABLE clean.services AS
SELECT DISTINCT clean.norm("ServiceID") AS service_id,
       clean.norm("ServiceName") AS service_name, clean.norm("DepartmentID") AS department_id
FROM raw.hc_services WHERE clean.norm("ServiceID") IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2. Patients (Phone column deliberately excluded: values corrupted
--    at the source, only 10 distinct values across all patients)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.patients CASCADE;
CREATE TABLE clean.patients AS
SELECT patient_id, first_name, last_name, gender, date_of_birth,
       age_declared, age_calc,
       CASE WHEN age_declared BETWEEN 0 AND 110 THEN age_declared::int
            WHEN age_calc     BETWEEN 0 AND 110 THEN age_calc END AS age,
       CASE WHEN COALESCE(CASE WHEN age_declared BETWEEN 0 AND 110 THEN age_declared END, age_calc) < 15 THEN '0-14'
            WHEN COALESCE(CASE WHEN age_declared BETWEEN 0 AND 110 THEN age_declared END, age_calc) < 25 THEN '15-24'
            WHEN COALESCE(CASE WHEN age_declared BETWEEN 0 AND 110 THEN age_declared END, age_calc) < 45 THEN '25-44'
            WHEN COALESCE(CASE WHEN age_declared BETWEEN 0 AND 110 THEN age_declared END, age_calc) < 65 THEN '45-64'
            WHEN COALESCE(CASE WHEN age_declared BETWEEN 0 AND 110 THEN age_declared END, age_calc) >= 65 THEN '65+' END AS age_group,
       marital_status, occupation, education, village_id, insurance_id,
       (insurance_id IS NOT NULL) AS is_insured,
       blood_group, height_cm, weight_kg, bmi,
       chronic_condition, (chronic_condition IS NOT NULL) AS has_chronic_disease,
       status
FROM (
  SELECT clean.norm("PatientID") AS patient_id,
         initcap(clean.norm("FirstName")) AS first_name,
         initcap(clean.norm("LastName"))  AS last_name,
         initcap(clean.norm("Gender"))    AS gender,
         clean.safe_date("DateOfBirth")   AS date_of_birth,
         clean.safe_num("Age")            AS age_declared,
         date_part('year', age(CURRENT_DATE, clean.safe_date("DateOfBirth")))::int AS age_calc,
         initcap(clean.norm("MaritalStatus")) AS marital_status,
         clean.norm("Occupation") AS occupation,
         clean.norm("Education")  AS education,
         clean.norm("VillageID")  AS village_id,
         clean.norm("InsuranceID") AS insurance_id,
         upper(clean.norm("BloodGroup")) AS blood_group,
         clean.safe_num("HeightCm") AS height_cm,
         clean.safe_num("WeightKg") AS weight_kg,
         clean.safe_num("BMI")      AS bmi,
         initcap(clean.norm("ChronicCondition")) AS chronic_condition,
         initcap(clean.norm("Status")) AS status,
         row_number() OVER (PARTITION BY clean.norm("PatientID") ORDER BY ctid) AS rn
  FROM raw.hc_patients) t
WHERE rn = 1 AND patient_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 3. Appointments (hc_clinical_transactions: 5,000 rows, from APT000001
--    to APT005000, while billing goes up to APT060000)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.appointments CASCADE;
CREATE TABLE clean.appointments AS
SELECT a.appointment_id, a.patient_id, a.doctor_id, a.facility_id, a.department_id,
       a.appointment_date, a.visit_type,
       (p.patient_id IS NOT NULL) AS patient_valid,
       EXISTS (SELECT 1 FROM clean.staff s
               WHERE s.staff_type = 'Doctor' AND s.staff_id = a.doctor_id) AS doctor_valid,
       (d.department_id IS NOT NULL) AS department_valid,
       COALESCE(d.facility_id = a.facility_id, false) AS facility_consistent,
       (a.appointment_date BETWEEN DATE '2020-01-01' AND DATE '2030-12-31') AS date_valid
FROM (
  SELECT clean.norm("AppointmentID") AS appointment_id,
         clean.norm("PatientID") AS patient_id,
         clean.norm("DoctorID") AS doctor_id,
         clean.norm("FacilityID") AS facility_id,
         clean.norm("DepartmentID") AS department_id,
         clean.safe_date("Date") AS appointment_date,
         CASE WHEN lower(clean.norm("VisitType")) IN ('follow-up', 'follow up', 'followup') THEN 'Follow-up'
              ELSE initcap(clean.norm("VisitType")) END AS visit_type,
         row_number() OVER (PARTITION BY clean.norm("AppointmentID") ORDER BY ctid) AS rn
  FROM raw.hc_clinical_transactions) a
LEFT JOIN clean.patients p    ON p.patient_id = a.patient_id
LEFT JOIN clean.departments d ON d.department_id = a.department_id
WHERE a.rn = 1 AND a.appointment_id IS NOT NULL;
CREATE UNIQUE INDEX ON clean.appointments (appointment_id);

-- ---------------------------------------------------------------------
-- 4. Finance: payments, billing, insurance claims
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.payments CASCADE;
CREATE TABLE clean.payments AS
SELECT payment_id, billing_id, amount_paid, method FROM (
  SELECT clean.norm("PaymentID") AS payment_id, clean.norm("BillingID") AS billing_id,
         clean.safe_num("AmountPaid") AS amount_paid, initcap(clean.norm("Method")) AS method,
         row_number() OVER (PARTITION BY clean.norm("PaymentID") ORDER BY ctid) AS rn
  FROM raw.hc_payments) t
WHERE rn = 1 AND payment_id IS NOT NULL;

DROP TABLE IF EXISTS clean.billing CASCADE;
CREATE TABLE clean.billing AS
SELECT b.billing_id, b.appointment_id, b.amount, b.status,
       COALESCE(p.paid, 0) AS amount_paid,
       b.amount - COALESCE(p.paid, 0) AS balance_due,
       (b.amount IS NOT NULL AND b.amount > 0) AS amount_valid,
       EXISTS (SELECT 1 FROM clean.appointments a
               WHERE a.appointment_id = b.appointment_id) AS has_appointment
FROM (
  SELECT clean.norm("BillingID") AS billing_id, clean.norm("AppointmentID") AS appointment_id,
         clean.safe_num("Amount") AS amount, initcap(lower(clean.norm("Status"))) AS status,
         row_number() OVER (PARTITION BY clean.norm("BillingID") ORDER BY ctid) AS rn
  FROM raw.hc_billing) b
LEFT JOIN (SELECT billing_id, SUM(amount_paid) AS paid FROM clean.payments GROUP BY 1) p
       ON p.billing_id = b.billing_id
WHERE b.rn = 1 AND b.billing_id IS NOT NULL;
CREATE UNIQUE INDEX ON clean.billing (billing_id);

DROP TABLE IF EXISTS clean.insurance_claims CASCADE;
CREATE TABLE clean.insurance_claims AS
SELECT claim_id, billing_id, provider, claim_amount, status FROM (
  SELECT clean.norm("ClaimID") AS claim_id, clean.norm("BillingID") AS billing_id,
         clean.norm("Provider") AS provider, clean.safe_num("ClaimAmount") AS claim_amount,
         initcap(lower(clean.norm("Status"))) AS status,
         row_number() OVER (PARTITION BY clean.norm("ClaimID") ORDER BY ctid) AS rn
  FROM raw.insurance_claims) t
WHERE rn = 1 AND claim_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 5. Clinical data and patient experience
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.diagnoses CASCADE;
CREATE TABLE clean.diagnoses AS
SELECT t.diagnosis_id, t.appointment_id, t.diagnosis, t.severity,
       EXISTS (SELECT 1 FROM clean.appointments a
               WHERE a.appointment_id = t.appointment_id) AS has_appointment
FROM (
  SELECT clean.norm("DiagnosisID") AS diagnosis_id, clean.norm("AppointmentID") AS appointment_id,
         initcap(clean.norm("Diagnosis")) AS diagnosis,
         initcap(lower(clean.norm("Severity"))) AS severity,
         row_number() OVER (PARTITION BY clean.norm("DiagnosisID") ORDER BY ctid) AS rn
  FROM raw.hc_diagnoses) t
WHERE t.rn = 1 AND t.diagnosis_id IS NOT NULL;

DROP TABLE IF EXISTS clean.patient_feedback CASCADE;
CREATE TABLE clean.patient_feedback AS
SELECT t.feedback_id, t.appointment_id, t.rating, t.comment,
       (t.rating BETWEEN 1 AND 5) AS rating_valid,
       EXISTS (SELECT 1 FROM clean.appointments a
               WHERE a.appointment_id = t.appointment_id) AS has_appointment
FROM (
  SELECT clean.norm("FeedbackID") AS feedback_id, clean.norm("AppointmentID") AS appointment_id,
         clean.safe_num("Rating")::int AS rating, clean.norm("Comment") AS comment,
         row_number() OVER (PARTITION BY clean.norm("FeedbackID") ORDER BY ctid) AS rn
  FROM raw.hc_patient_feedback) t
WHERE t.rn = 1 AND t.feedback_id IS NOT NULL;

DROP TABLE IF EXISTS clean.revenue_summary CASCADE;
CREATE TABLE clean.revenue_summary AS
SELECT clean.safe_date(clean.norm("Month") || '-01') AS month,
       clean.safe_num("Revenue") AS revenue,
       clean.safe_num("Appointments") AS appointments_declared
FROM raw.hc_revenue_summary;

-- ---------------------------------------------------------------------
-- 6. Data quality report
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean.dq_report;
CREATE TABLE clean.dq_report (
  id serial PRIMARY KEY, domaine text, controle text, table_concernee text,
  anomalies bigint, total bigint, pct numeric(6,2), traitement text);

INSERT INTO clean.dq_report (domaine, controle, table_concernee, anomalies, total, traitement)
-- Duplicates
SELECT 'Unicité', 'Doublons de PatientID', 'hc_patients',
       COUNT("PatientID") - COUNT(DISTINCT "PatientID"), COUNT(*), 'Premier enregistrement conservé' FROM raw.hc_patients
UNION ALL SELECT 'Unicité', 'Doublons de AppointmentID', 'hc_clinical_transactions',
       COUNT("AppointmentID") - COUNT(DISTINCT "AppointmentID"), COUNT(*), 'Premier enregistrement conservé' FROM raw.hc_clinical_transactions
UNION ALL SELECT 'Unicité', 'Doublons de BillingID', 'hc_billing',
       COUNT("BillingID") - COUNT(DISTINCT "BillingID"), COUNT(*), 'Premier enregistrement conservé' FROM raw.hc_billing
UNION ALL SELECT 'Unicité', 'Patients en double (prénom + nom + date de naissance)', 'patients',
       COALESCE((SELECT SUM(c - 1) FROM (SELECT COUNT(*) AS c FROM clean.patients
                 GROUP BY first_name, last_name, date_of_birth HAVING COUNT(*) > 1) x), 0),
       (SELECT COUNT(*) FROM clean.patients), 'Signalés, non supprimés (homonymes possibles)'
-- Patients
UNION ALL SELECT 'Validité', 'Date de naissance absente ou illisible', 'patients',
       COUNT(*) FILTER (WHERE date_of_birth IS NULL), COUNT(*), 'Âge recalculé impossible, âge déclaré utilisé' FROM clean.patients
UNION ALL SELECT 'Validité', 'Âge impossible (absent, négatif ou > 110)', 'patients',
       COUNT(*) FILTER (WHERE age_declared IS NULL OR age_declared NOT BETWEEN 0 AND 110), COUNT(*), 'Remplacé par l''âge calculé quand possible' FROM clean.patients
UNION ALL SELECT 'Cohérence', 'Âge déclaré différent de l''âge calculé (> 1 an)', 'patients',
       COUNT(*) FILTER (WHERE age_calc IS NOT NULL AND age_declared IS NOT NULL AND abs(age_calc - age_declared) > 1),
       COUNT(*), 'Signalé, âge déclaré conservé' FROM clean.patients
UNION ALL SELECT 'Validité', 'Colonne Phone inexploitable (très peu de valeurs distinctes)', 'hc_patients',
       CASE WHEN COUNT(DISTINCT "Phone") < 0.01 * COUNT(*) THEN COUNT(*) ELSE 0 END, COUNT(*),
       'Colonne exclue de clean.patients, corrompue à la source' FROM raw.hc_patients
-- Referential integrity of appointments
UNION ALL SELECT 'Intégrité', 'Rendez-vous avec patient inexistant', 'appointments',
       COUNT(*) FILTER (WHERE NOT patient_valid), COUNT(*), 'Conservés, exclus des analyses patient' FROM clean.appointments
UNION ALL SELECT 'Intégrité', 'Rendez-vous avec médecin inexistant', 'appointments',
       COUNT(*) FILTER (WHERE NOT doctor_valid), COUNT(*), 'Conservés, exclus des analyses médecin' FROM clean.appointments
UNION ALL SELECT 'Intégrité', 'Rendez-vous avec département inexistant', 'appointments',
       COUNT(*) FILTER (WHERE NOT department_valid), COUNT(*), 'Conservés, exclus des analyses département' FROM clean.appointments
UNION ALL SELECT 'Cohérence', 'Département n''appartenant pas à l''établissement indiqué', 'appointments',
       COUNT(*) FILTER (WHERE department_valid AND NOT facility_consistent), COUNT(*), 'Signalés' FROM clean.appointments
UNION ALL SELECT 'Validité', 'Date de rendez-vous absente, illisible ou hors plage 2020-2030', 'appointments',
       COUNT(*) FILTER (WHERE NOT date_valid), COUNT(*), 'Exclus des analyses temporelles' FROM clean.appointments
UNION ALL SELECT 'Information', 'Rendez-vous postérieurs à la date du jour (le jeu de données couvre toute l''année 2026)', 'appointments',
       COUNT(*) FILTER (WHERE appointment_date > CURRENT_DATE), COUNT(*), 'Conservés, considérés comme valides' FROM clean.appointments
-- Finance
UNION ALL SELECT 'Intégrité', 'Factures sans rendez-vous correspondant', 'billing',
       COUNT(*) FILTER (WHERE NOT has_appointment), COUNT(*), 'Conservées pour les analyses financières globales' FROM clean.billing
UNION ALL SELECT 'Validité', 'Montant de facture absent ou <= 0', 'billing',
       COUNT(*) FILTER (WHERE NOT amount_valid), COUNT(*), 'Exclus des calculs de revenu' FROM clean.billing
UNION ALL SELECT 'Cohérence', 'Statut Paid avec solde restant', 'billing',
       COUNT(*) FILTER (WHERE status = 'Paid' AND balance_due > 0), COUNT(*), 'Signalé' FROM clean.billing
UNION ALL SELECT 'Cohérence', 'Statut Pending avec paiement enregistré', 'billing',
       COUNT(*) FILTER (WHERE status = 'Pending' AND amount_paid > 0), COUNT(*), 'Signalé' FROM clean.billing
UNION ALL SELECT 'Cohérence', 'Montant payé supérieur au montant facturé', 'billing',
       COUNT(*) FILTER (WHERE amount_valid AND amount_paid > amount), COUNT(*), 'Signalé' FROM clean.billing
UNION ALL SELECT 'Intégrité', 'Paiements sans facture', 'payments',
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM clean.billing b WHERE b.billing_id = p.billing_id)),
       COUNT(*), 'Signalés' FROM clean.payments p
UNION ALL SELECT 'Intégrité', 'Réclamations sans facture', 'insurance_claims',
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM clean.billing b WHERE b.billing_id = c.billing_id)),
       COUNT(*), 'Signalées' FROM clean.insurance_claims c
UNION ALL SELECT 'Cohérence', 'Montant réclamé supérieur au montant facturé', 'insurance_claims',
       COUNT(*) FILTER (WHERE c.claim_amount > b.amount), COUNT(*), 'Signalées'
       FROM clean.insurance_claims c JOIN clean.billing b ON b.billing_id = c.billing_id
-- Clinical and satisfaction
UNION ALL SELECT 'Intégrité', 'Diagnostics sans rendez-vous correspondant', 'diagnoses',
       COUNT(*) FILTER (WHERE NOT has_appointment), COUNT(*), 'Conservés pour les analyses globales' FROM clean.diagnoses
UNION ALL SELECT 'Intégrité', 'Avis patients sans rendez-vous correspondant', 'patient_feedback',
       COUNT(*) FILTER (WHERE NOT has_appointment), COUNT(*), 'Conservés pour les analyses globales' FROM clean.patient_feedback
UNION ALL SELECT 'Validité', 'Note hors de l''échelle 1 à 5', 'patient_feedback',
       COUNT(*) FILTER (WHERE NOT COALESCE(rating_valid, false)), COUNT(*), 'Exclues des moyennes' FROM clean.patient_feedback
-- Staff
UNION ALL SELECT 'Validité', 'Années d''expérience absentes, négatives ou > 50', 'staff',
       COUNT(*) FILTER (WHERE years_experience IS NULL OR years_experience NOT BETWEEN 0 AND 50), COUNT(*), 'Exclues des moyennes' FROM clean.staff
UNION ALL SELECT 'Intégrité', 'Personnel avec département inexistant', 'staff',
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM clean.departments d WHERE d.department_id = s.department_id)),
       COUNT(*), 'Signalé' FROM clean.staff s;

UPDATE clean.dq_report SET pct = round(100.0 * anomalies / NULLIF(total, 0), 2);

-- ---------------------------------------------------------------------
-- 7. Results to review
-- ---------------------------------------------------------------------
SELECT * FROM clean.dq_report ORDER BY id;

SELECT 'patients' AS table_clean, COUNT(*) FROM clean.patients
UNION ALL SELECT 'appointments', COUNT(*) FROM clean.appointments
UNION ALL SELECT 'billing', COUNT(*) FROM clean.billing
UNION ALL SELECT 'payments', COUNT(*) FROM clean.payments
UNION ALL SELECT 'insurance_claims', COUNT(*) FROM clean.insurance_claims
UNION ALL SELECT 'diagnoses', COUNT(*) FROM clean.diagnoses
UNION ALL SELECT 'patient_feedback', COUNT(*) FROM clean.patient_feedback
UNION ALL SELECT 'staff', COUNT(*) FROM clean.staff;