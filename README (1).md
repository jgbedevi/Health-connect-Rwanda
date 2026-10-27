# HealthConnect Rwanda: Healthcare Operations and Performance Analytics

AnalystLab Africa Experience Lab, Week 6, Data Analytics track.
Author: Yawa Jacqueline GBEDEVI

This project turns the HealthConnect Rwanda healthcare data (patients, appointments, diagnoses, billing, insurance claims, payments, patient feedback, staff and infrastructure) into a cleaned PostgreSQL database, 40 SQL analyses and a six-page Power BI dashboard for hospital executives.

## Repository structure

```
.
├── sql/
│   ├── cleaning.sql   cleaning, validation, data quality report
│   ├── analytics.sql         analytical views used by SQL queries and Power BI
│   └── requete.sql           the 40 business queries
├── database/
│   └── healthconnect_rwanda.backup   PostgreSQL backup (pg_dump, custom format)
├── Dashboard/
│   ├── HealthConnect_Dashboard.pbix
│   ├── HealthConnect_Dashboard.pdf   executive dashboard export
├── Data/
├── docs/
│   ├── Business_Insights_Report.pdf
│   ├── HealthConnect Rwanda Executive Presentation.pdf
│                   
└── README.md
```

## How to reproduce

Requirements: PostgreSQL 14 or later, Power BI Desktop.

1. Create the database and import the source files as text into a schema named `raw` (one table per file, original column names kept, nothing modified).
2. Run the scripts in order, each in full:
   1. `sql/cleaning.sql` builds the `clean` schema and the table `clean.dq_report`.
   2. `sql/analytics.sql` builds the `analytics` schema (views and dimensions).
   3. `sql/requete.sql` runs the 40 queries.
3. Commit the transaction at the end of script 01, otherwise the percentage column of the data quality report stays empty.
4. To restore the backup instead of rebuilding:
   ```
   createdb healthconnect_rwanda
   pg_restore -d healthconnect_rwanda database/healthconnect_rwanda.backup
   ```
5. Open the `.pbix`, then update the PostgreSQL connection (Transform data > Data source settings) to point to your server.

The raw schema is never modified. Every correction happens in `clean`, so each cleaning step can be replayed.

## Data

27 source tables were imported. The relevant volumes after cleaning are below.

| Table | Rows |
|---|---|
| Patients | 20,000 |
| Appointments (hc_clinical_transactions) | 5,000 |
| Billing | 60,000 |
| Payments | 60,000 |
| Insurance claims | 42,036 |
| Diagnoses | 60,000 |
| Patient feedback | 21,064 |
| Staff (all categories) | 1,250 |

`hc_facility_master_data` has the same columns as `hc_departments` and was not used.

## Data quality findings

The full list of 26 checks is in `clean.dq_report`. The points that shape the analysis are:

- **Appointments are incomplete.** The appointment table stops at APT005000 (5,000 rows, confirmed against the source file), while billing, diagnoses and feedback reference appointments up to APT060000. Only about 8% of bills, diagnoses and feedback records can be linked to a facility, a department, a date or a patient province. Analyses by facility, department, province or month cover that 8%. Global financial analyses (total billed, collected, outstanding, claims by provider, payment methods) use all 60,000 bills.
- **Phone numbers are corrupted at the source.** The column holds 10 distinct values for 20,000 patients (scientific notation lost the digits). It was excluded from the clean data, so duplicate detection by phone is not possible.
- **Facility and department are inconsistent.** For 95% of appointments the department does not belong to the facility recorded on the appointment. The two dimensions are therefore analysed separately and never related to each other.
- **Billing status does not match payments.** Every bill marked Pending has a payment recorded, and some bills marked Paid still carry a balance. Outstanding amounts are computed as billed minus collected, whatever the status label says.
- **Revenue totals do not reconcile.** Billed amounts total 9.31 billion, payments 8.39 billion, and the provided monthly revenue summary only 1.13 billion. The summary table is reported as an unexplained gap and is not used for KPIs.
- **Patient names repeat.** Many patients share first name, last name and date of birth, but patient IDs are unique. They are treated as homonyms and nothing was deleted.
- **Appointment dates run through December 2026,** including dates after the day of the analysis. They were kept as valid, and no measure relies on today's date.

## What could not be done

The dataset has no admissions, laboratory test, prescription or referral tables, no facility master table and no registration date. As a result:

- Queries 22, 23, 24, 26, 27 and 28 return an explicit "not possible" message.
- Query 29 uses the share of severe cases as a proxy for admission rate.
- Query 33 reports revenue by department, since bills carry no service.
- Referral rate, cancellation rate, admission rate, average length of stay, readmission, lab and prescription KPIs are not calculated.
- All beds are recorded as Available, so bed utilization would show 0% and is not interpreted. Equipment has no status field, so only its distribution is shown.
- Hospitals appear as facility IDs, not names.

## Power BI dashboard

Six pages (executive, patient analytics, clinical analytics, financial, operational, patient experience) plus a facility drill-through page and a tooltip page. 



## Tools

PostgreSQL, SQL, Power BI (DAX).


