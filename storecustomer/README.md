# Privacy-First Sales Analytics Pilot (Car Dealership)

## Overview
![Power BI dashboard overview](https://github.com/pakitt/data-analysis-portfolio/blob/main/storecustomer/images/dashboard_overview.png)

Proof-of-concept analytics pipeline and dashboard built during the *[Generation UK & Ireland] (https://ireland.generation.org/)* placement period (December 2025 - May 2026).  
The project demonstrates how a multi-branch car dealership can analyze sales performance and customer behavior **without exposing any personally identifiable information (PII)**.

The emphasis is on **process, data governance, and analytical reasoning**, not on statistical depth.

---

## Problem
Local businesses requested a pilot system to:
- Visualize sales and profit by store
- Understand customer buying habits
- Analyze payment methods (cash vs card)
- Receive guidance on suitable visualizations
- Run locally (Windows/macOS)
- Ensure full anonymization of client and payment data
- Remain scalable for future expansion

A **small synthetic raw text file (~60 rows)** was provided as a subset of a larger hypothetical dataset.

---

## Design Principles
Consistent with my earlier fuel / EV analytics project:
- Privacy by design
- Minimal, explicit data pipeline
- Clear separation between raw data and BI layer
- Analytical honesty over decorative dashboards
- Proof-of-concept before scale

---

## Architecture
![Data pipeline and anonymization flow](https://github.com/pakitt/data-analysis-portfolio/blob/main/storecustomer/images/pipeline_arch.png)
**Toolchain (intentionally minimal):**
- **Python** – ingestion, parsing, anonymization, export
- **Power BI** – visualization and exploratory analysis

**Flow:**
→ Python ingestion & parsing
→ Early anonymization (PII removed)
→ Clean CSV
→ Power BI dashboard
Power BI never accesses customer names or card details.

---

## Privacy & Anonymization
- PII removed at ingestion, not downstream
- Deterministic anonymization:
  - Same customer → same anonymized ID
  - Enables behavior analysis without re-identification
- BI layer operates exclusively on non-sensitive data

This aligns with GDPR “privacy by design” principles.

---

## Analytical Assumptions
- Fixed **40% markup** for all sales (per requirements)
- Profit is therefore proportional to revenue  
  → Profit rankings add no new information

**Focus instead on:**
- Revenue by store
- Revenue by customer
- Customer concentration
- Payment method preferences

This is a deliberate analytical choice.

---

## Scalability
- Python pipeline is data-volume agnostic
- Anonymization logic reusable unchanged
- CSV output easily replaced by databases or cloud storage
- Power BI dashboards can migrate to cloud or on-prem environments

---

## Notes
- All data is synthetic
- No real customer or payment information is used
- This project is a technical and analytical demonstration
