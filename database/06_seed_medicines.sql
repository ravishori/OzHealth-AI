-- ============================================================
-- VitaPulse AI - Australian Medicines Seed Data
-- Based on TGA ARTG (Australian Register of Therapeutic Goods)
-- Run after 05_functions_procedures.sql
-- ============================================================

\c VitaPulse_DB

-- ─────────────────────────────────────────────
-- Analgesics / Antipyretics
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Paracetamol 500mg Tablets',
    'Paracetamol',
    '["Panadol", "Panamax", "Dymadon", "Chemists Own Paracetamol"]',
    'Paracetamol 500 mg per tablet',
    'Analgesic / Antipyretic',
    '["tablet"]',
    'Adults: 1–2 tablets (500–1000 mg) every 4–6 hours. Max 4 g/day (8 tablets). Children: dose by weight.',
    'Rare at therapeutic doses. Overdose causes serious liver damage.',
    'Warfarin (increased INR with regular use). Alcohol increases hepatotoxicity risk.',
    'Severe hepatic impairment. Known hypersensitivity to paracetamol.',
    'Do NOT exceed recommended dose. Avoid alcohol. Check all other medicines for paracetamol content to avoid double dosing.',
    'Store below 25°C. Keep out of reach of children.',
    'A',
    TRUE, 'ARTG-001234',
    'S2', 'N02BE01'
),
(
    'Ibuprofen 200mg Tablets',
    'Ibuprofen',
    '["Nurofen", "Advil", "Rafen", "Chemists Own Ibuprofen"]',
    'Ibuprofen 200 mg per tablet',
    'NSAID (Non-Steroidal Anti-Inflammatory Drug)',
    '["tablet", "capsule", "liquid gel capsule"]',
    'Adults and children ≥12 years: 200–400 mg every 4–6 hours. Max 1200 mg/day (OTC).',
    'GI upset, nausea, heartburn, headache. Rare: peptic ulcer, renal impairment, cardiovascular events.',
    'Aspirin, other NSAIDs, warfarin, lithium, methotrexate, ACE inhibitors.',
    'Active peptic ulcer, severe renal/hepatic impairment, third trimester pregnancy, NSAID hypersensitivity.',
    'Take with food or milk to reduce GI upset. Use lowest effective dose for shortest duration. Avoid in dehydration.',
    'Store below 30°C. Keep dry.',
    'C',
    TRUE, 'ARTG-002345',
    'S2', 'M01AE01'
),
(
    'Aspirin 300mg Tablets',
    'Aspirin (Acetylsalicylic acid)',
    '["Aspro", "Disprin", "Solprin"]',
    'Aspirin 300 mg per tablet',
    'NSAID / Antiplatelet',
    '["tablet", "effervescent tablet"]',
    'Analgesic: 300–900 mg every 4–6 hours. Max 4 g/day. Antiplatelet: 100 mg daily (S4 doses).',
    'GI irritation, bleeding, tinnitus at high doses. Rare: Reye syndrome in children.',
    'Anticoagulants, other NSAIDs, methotrexate, valproate.',
    'Children under 16 years (risk of Reye syndrome). Active peptic ulcer. Haemophilia.',
    'NOT for use in children under 16. Do not use for fever in children/teenagers.',
    'Store below 25°C in a dry place.',
    'C',
    TRUE, 'ARTG-003456',
    'S2', 'N02BA01'
);

-- ─────────────────────────────────────────────
-- Antibiotics
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Amoxicillin 500mg Capsules',
    'Amoxicillin',
    '["Amoxil", "Alphamox", "Cilamox"]',
    'Amoxicillin trihydrate equivalent to 500 mg amoxicillin per capsule',
    'Antibiotic — Aminopenicillin',
    '["capsule", "tablet", "suspension"]',
    'Adults: 250–500 mg every 8 hours or 500–875 mg every 12 hours depending on infection severity.',
    'Nausea, diarrhoea, rash. Rare: anaphylaxis, pseudomembranous colitis.',
    'Warfarin, methotrexate, oral contraceptives (reduced efficacy). Allopurinol increases rash risk.',
    'Penicillin or cephalosporin hypersensitivity.',
    'Stop immediately and seek medical help if rash, swelling, or breathing difficulty develops.',
    'Store capsules below 25°C. Reconstituted suspension: refrigerate, use within 7 days.',
    'A',
    TRUE, 'ARTG-010234',
    'S4', 'J01CA04'
),
(
    'Cefalexin 500mg Capsules',
    'Cefalexin (Cephalexin)',
    '["Keflex", "Ibilex", "Maracef"]',
    'Cefalexin monohydrate equivalent to 500 mg cefalexin per capsule',
    'Antibiotic — First-generation Cephalosporin',
    '["capsule", "tablet", "suspension"]',
    'Adults: 250–500 mg every 6 hours or 500 mg–1 g every 12 hours.',
    'Diarrhoea, nausea, abdominal discomfort, hypersensitivity reactions.',
    'Probenecid (increased cefalexin levels), warfarin.',
    'Known allergy to cephalosporins. Use with caution in penicillin-allergic patients.',
    'Cross-reactivity with penicillins possible (~1–2%). Complete the full course.',
    'Store below 25°C. Suspension: refrigerate, use within 14 days.',
    'A',
    TRUE, 'ARTG-011345',
    'S4', 'J01DB01'
),
(
    'Azithromycin 500mg Tablets',
    'Azithromycin',
    '["Zithromax", "Azibiot", "Azenil"]',
    'Azithromycin dihydrate equivalent to 500 mg azithromycin per tablet',
    'Antibiotic — Macrolide',
    '["tablet", "capsule", "suspension"]',
    'Adults: 500 mg on Day 1, then 250 mg on Days 2–5. Or 500 mg daily for 3 days.',
    'Nausea, diarrhoea, abdominal pain. Rare: QT prolongation, liver enzyme elevation.',
    'Antacids reduce absorption (take 1 hour before or 2 hours after). Digoxin, warfarin, ergotamine, QT-prolonging drugs.',
    'Hepatic impairment. Known hypersensitivity to macrolides.',
    'May prolong QT interval — use with caution in patients with cardiac conditions.',
    'Store below 30°C.',
    'B1',
    TRUE, 'ARTG-012456',
    'S4', 'J01FA10'
);

-- ─────────────────────────────────────────────
-- Cardiovascular
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Atorvastatin 20mg Tablets',
    'Atorvastatin',
    '["Lipitor", "Lorstat", "Atorvastatin AN"]',
    'Atorvastatin calcium equivalent to 20 mg atorvastatin per tablet',
    'HMG-CoA Reductase Inhibitor (Statin)',
    '["tablet"]',
    'Initial: 10–20 mg once daily. Dose range: 10–80 mg/day. Take at any time of day.',
    'Muscle pain/weakness (myopathy), elevated liver enzymes, headache, GI upset. Rare: rhabdomyolysis.',
    'Cyclosporine, fibrates, niacin, antifungals, macrolide antibiotics (increase statin levels). Grapefruit juice.',
    'Active liver disease. Unexplained persistent elevation of liver transaminases. Pregnancy and breastfeeding.',
    'Report unexplained muscle pain, tenderness, or weakness immediately. Avoid grapefruit juice.',
    'Store below 25°C.',
    'D',
    TRUE, 'ARTG-020123',
    'S4', 'C10AA05'
),
(
    'Perindopril 5mg Tablets',
    'Perindopril',
    '["Coversyl", "Perindo", "Perindopril AN"]',
    'Perindopril arginine 6.79 mg equivalent to 5 mg perindopril per tablet',
    'ACE Inhibitor (Antihypertensive)',
    '["tablet"]',
    'Hypertension: 5–10 mg once daily. Heart failure: start 2.5 mg, titrate up.',
    'Dry persistent cough (very common), dizziness, hypotension (first dose), hyperkalaemia, angioedema (rare but serious).',
    'Potassium-sparing diuretics, potassium supplements, NSAIDs, lithium, aliskiren.',
    'History of angioedema with ACE inhibitor. Pregnancy (second and third trimester). Bilateral renal artery stenosis.',
    'First-dose hypotension especially in dehydrated or diuretic-treated patients. Stop immediately if angioedema occurs.',
    'Store below 25°C. Protect from moisture.',
    'D',
    TRUE, 'ARTG-021234',
    'S4', 'C09AA04'
),
(
    'Metoprolol 50mg Tablets',
    'Metoprolol succinate',
    '["Lopressor", "Metohexal", "Toprol"]',
    'Metoprolol succinate equivalent to 50 mg metoprolol per tablet',
    'Cardioselective Beta-1 Blocker',
    '["tablet", "extended-release tablet"]',
    'Hypertension/angina: 50–100 mg once or twice daily. Heart failure: start 12.5–25 mg, titrate slowly.',
    'Fatigue, bradycardia, cold extremities, dizziness, sexual dysfunction, bronchospasm (less than non-selective).',
    'Verapamil/diltiazem (bradycardia risk), other antihypertensives, clonidine, insulin (masks hypoglycaemia signs).',
    'Severe bradycardia, sick sinus syndrome, severe peripheral arterial disease, cardiogenic shock, uncontrolled heart failure.',
    'Do NOT stop abruptly — taper over ≥2 weeks. Use with caution in asthma/COPD.',
    'Store below 25°C.',
    'C',
    TRUE, 'ARTG-022345',
    'S4', 'C07AB02'
),
(
    'Clopidogrel 75mg Tablets',
    'Clopidogrel',
    '["Plavix", "Iscover", "Clopidogrel AN"]',
    'Clopidogrel bisulfate equivalent to 75 mg clopidogrel per tablet',
    'Antiplatelet Agent (P2Y12 inhibitor)',
    '["tablet"]',
    'Maintenance: 75 mg once daily. Loading dose: 300–600 mg (hospital use).',
    'Bleeding (most common), bruising, GI upset, rash. Rare: TTP.',
    'Aspirin (increased bleeding risk — often co-prescribed), NSAIDs, warfarin, omeprazole (may reduce efficacy), PPIs.',
    'Active pathological bleeding (peptic ulcer, intracranial haemorrhage). Severe hepatic impairment.',
    'Inform all healthcare providers including dentist before procedures. Do not stop without medical advice.',
    'Store below 30°C.',
    'B1',
    TRUE, 'ARTG-023456',
    'S4', 'B01AC04'
);

-- ─────────────────────────────────────────────
-- Diabetes Management
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Metformin 500mg Tablets',
    'Metformin hydrochloride',
    '["Glucophage", "Diaformin", "Metformin AN", "Diabex"]',
    'Metformin hydrochloride 500 mg per tablet',
    'Biguanide Antidiabetic',
    '["tablet", "extended-release tablet"]',
    'Initial: 500 mg twice daily with meals. Increase gradually. Usual maintenance: 1500–2000 mg/day in divided doses.',
    'GI effects: nausea, diarrhoea, abdominal discomfort (usually transient). Rare: lactic acidosis (very rare at therapeutic doses). Long-term B12 deficiency.',
    'Iodinated contrast media (hold 48h before/after). Alcohol (lactic acidosis risk). Cimetidine.',
    'eGFR <30 mL/min. Metabolic acidosis. Hepatic impairment. Excessive alcohol use.',
    'Hold before iodinated contrast procedures. Monitor renal function annually. Monitor B12 levels with long-term use.',
    'Store below 30°C.',
    'C',
    TRUE, 'ARTG-030123',
    'S4', 'A10BA02'
),
(
    'Sitagliptin 100mg Tablets',
    'Sitagliptin',
    '["Januvia", "Sitagliptin AN"]',
    'Sitagliptin phosphate monohydrate equivalent to 100 mg sitagliptin per tablet',
    'DPP-4 Inhibitor (Dipeptidyl Peptidase-4)',
    '["tablet"]',
    'Type 2 diabetes: 100 mg once daily. Dose adjustment required in renal impairment.',
    'Nasopharyngitis, headache, upper respiratory infections. Rare: pancreatitis, hypersensitivity, joint pain.',
    'Digoxin (slight increase in digoxin levels). Insulin/sulfonylureas (hypoglycaemia risk).',
    'Type 1 diabetes. Diabetic ketoacidosis.',
    'Discontinue if pancreatitis suspected. Monitor renal function.',
    'Store below 25°C.',
    'B1',
    TRUE, 'ARTG-031234',
    'S4', 'A10BH01'
),
(
    'Empagliflozin 10mg Tablets',
    'Empagliflozin',
    '["Jardiance"]',
    'Empagliflozin 10 mg per tablet',
    'SGLT-2 Inhibitor (Sodium-Glucose Cotransporter-2)',
    '["tablet"]',
    'Type 2 diabetes / heart failure / CKD: 10 mg once daily in the morning. May increase to 25 mg.',
    'UTI, genital mycotic infections, polyuria, DKA (rare), hypotension, Fournier''s gangrene (very rare).',
    'Diuretics (increased risk of dehydration/hypotension), insulin (hypoglycaemia).',
    'eGFR <20 mL/min. Type 1 diabetes (not indicated). Recurrent genital infections.',
    'Withhold before major surgery or prolonged fasting. Check for DKA symptoms even with near-normal glucose.',
    'Store below 30°C.',
    'B1',
    TRUE, 'ARTG-032345',
    'S4', 'A10BK03'
);

-- ─────────────────────────────────────────────
-- Respiratory
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Salbutamol 100mcg Inhaler',
    'Salbutamol (Albuterol)',
    '["Ventolin", "Airomir", "Asmol"]',
    'Salbutamol sulfate equivalent to 100 mcg salbutamol per actuation',
    'Short-Acting Beta-2 Agonist (SABA) — Bronchodilator',
    '["inhaler (MDI)", "nebuliser solution"]',
    'Acute relief: 1–2 puffs as needed. Exercise-induced: 2 puffs 15 min before exercise. Max 8 puffs/24h (without medical review).',
    'Tremor, palpitations, tachycardia, headache, hypokalaemia with high doses.',
    'Beta-blockers (antagonise bronchodilation), other sympathomimetics, diuretics (hypokalaemia).',
    'Known hypersensitivity to salbutamol. Not for maintenance therapy alone in persistent asthma.',
    'If using more than 3 times/week for symptom relief, reassess asthma control — consider adding inhaled corticosteroid.',
    'Store below 30°C. Protect from frost and direct sunlight.',
    'A',
    TRUE, 'ARTG-040123',
    'S3', 'R03AC02'
),
(
    'Fluticasone/Salmeterol 250/25mcg Inhaler',
    'Fluticasone propionate / Salmeterol',
    '["Seretide", "Fluticasone/Salmeterol Sandoz"]',
    'Fluticasone propionate 250 mcg + Salmeterol 25 mcg per actuation',
    'Inhaled Corticosteroid + Long-Acting Beta-2 Agonist (ICS/LABA)',
    '["inhaler (MDI)", "dry powder inhaler (Accuhaler)"]',
    'Adults: 2 puffs twice daily. Do not use for acute attacks.',
    'Hoarseness, oral candidiasis (rinse mouth after use), dysphonia, increased risk of pneumonia.',
    'Ketoconazole, ritonavir (increase fluticasone levels). Beta-blockers (antagonise salmeterol).',
    'Acute asthma attack (use salbutamol). Not for children under 4 years.',
    'NOT a rescue inhaler. Always have salbutamol available. Rinse mouth after each dose to prevent oral thrush.',
    'Store below 30°C. Do not refrigerate.',
    'B3',
    TRUE, 'ARTG-041234',
    'S4', 'R03AK06'
);

-- ─────────────────────────────────────────────
-- Gastrointestinal
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Omeprazole 20mg Capsules',
    'Omeprazole',
    '["Losec", "Prilosec", "Omeprazole AN", "Omezol"]',
    'Omeprazole 20 mg (as magnesium trihydrate) per capsule',
    'Proton Pump Inhibitor (PPI)',
    '["capsule", "tablet"]',
    'GORD/peptic ulcer: 20–40 mg once daily before breakfast. H. pylori eradication: as part of triple therapy.',
    'Headache, diarrhoea, nausea, abdominal pain, flatulence. Long-term: hypomagnesaemia, B12 deficiency, C. diff risk.',
    'Clopidogrel (reduced antiplatelet effect), methotrexate, atazanavir/nelfinavir (avoid), warfarin, digoxin.',
    'Known hypersensitivity to PPIs.',
    'Use lowest effective dose for shortest duration. Long-term use (>1 year) increases fracture and C. diff risk.',
    'Store below 25°C. Keep in original container.',
    'B3',
    TRUE, 'ARTG-050123',
    'S3', 'A02BC01'
),
(
    'Ondansetron 4mg Tablets',
    'Ondansetron',
    '["Zofran", "Ondansetron AN", "Ondaz"]',
    'Ondansetron hydrochloride dihydrate equivalent to 4 mg ondansetron per tablet',
    '5-HT3 Receptor Antagonist (Antiemetic)',
    '["tablet", "wafer (ODT)", "injection"]',
    'Nausea/vomiting: 4–8 mg every 8–12 hours. Chemotherapy: 8 mg before + 8 mg 8h after.',
    'Headache, constipation, flushing. Rare: QT prolongation, serotonin syndrome.',
    'Apomorphine (contraindicated — profound hypotension). Serotonergic drugs. QT-prolonging drugs.',
    'Concomitant use of apomorphine.',
    'May mask signs of ileus. ECG monitoring recommended in high-risk patients for QT prolongation.',
    'Store below 30°C.',
    'B1',
    TRUE, 'ARTG-051234',
    'S4', 'A04AA01'
);

-- ─────────────────────────────────────────────
-- Mental Health
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Sertraline 50mg Tablets',
    'Sertraline',
    '["Zoloft", "Sertra", "Sertraline AN"]',
    'Sertraline hydrochloride equivalent to 50 mg sertraline per tablet',
    'SSRI (Selective Serotonin Reuptake Inhibitor) — Antidepressant',
    '["tablet", "capsule"]',
    'Depression/anxiety: 50 mg once daily. May increase to 200 mg/day. Takes 2–6 weeks for full effect.',
    'Nausea, diarrhoea, insomnia, dry mouth, sexual dysfunction, weight changes. Rare: serotonin syndrome, SIADH.',
    'MAOIs (contraindicated, fatal — 14-day washout required). Tramadol, triptans, lithium (serotonin syndrome risk). Warfarin (increased bleeding). NSAIDs/aspirin (bleeding risk).',
    'Concurrent MAOI use or within 14 days of stopping MAOI. Hypersensitivity to sertraline.',
    'Monitor for suicidal ideation especially in patients under 25 in early treatment. Do not stop abruptly.',
    'Store below 30°C.',
    'B1',
    TRUE, 'ARTG-060123',
    'S4', 'N06AB06'
),
(
    'Escitalopram 10mg Tablets',
    'Escitalopram',
    '["Lexapro", "Esipram", "Escitalopram AN"]',
    'Escitalopram oxalate equivalent to 10 mg escitalopram per tablet',
    'SSRI (Selective Serotonin Reuptake Inhibitor) — Antidepressant/Anxiolytic',
    '["tablet"]',
    'Depression/GAD: 10 mg once daily. Max 20 mg/day (10 mg in elderly/hepatic impairment).',
    'Nausea, insomnia, increased sweating, sexual dysfunction, QT prolongation (dose-related).',
    'MAOIs (contraindicated). QT-prolonging drugs (additive effect). Lithium, tramadol, triptans.',
    'Concurrent MAOI use. QTc >450 ms. Congenital long QT syndrome.',
    'ECG recommended if QT risk factors present. Monitor young patients for suicidal ideation.',
    'Store below 30°C.',
    'B1',
    TRUE, 'ARTG-061234',
    'S4', 'N06AB10'
);

-- ─────────────────────────────────────────────
-- Vitamins & Supplements (Unscheduled / S2)
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Vitamin D3 1000IU Tablets',
    'Colecalciferol (Vitamin D3)',
    '["Ostelin", "Devarix", "Bio-D", "Blackmores Vitamin D"]',
    'Colecalciferol 25 mcg (1000 IU) per tablet',
    'Vitamin D Supplement',
    '["tablet", "capsule", "drops"]',
    'Adults: 1000–2000 IU daily for maintenance. Deficiency treatment: as directed by doctor (up to 50,000 IU/week).',
    'Usually well tolerated. Toxicity (with excess doses): hypercalcaemia, hypercalciuria, nausea, weakness.',
    'Thiazide diuretics (hypercalcaemia risk). Calcium supplements.',
    'Hypercalcaemia. Vitamin D toxicity.',
    'Prolonged high-dose use without monitoring may cause toxicity. Check blood calcium periodically.',
    'Store below 25°C. Protect from light.',
    'A',
    TRUE, 'ARTG-070123',
    'Unscheduled', 'A11CC05'
),
(
    'Folic Acid 500mcg Tablets',
    'Folic Acid',
    '["Megafol", "Folinz", "Blackmores Folic Acid"]',
    'Folic acid 500 mcg per tablet',
    'Water-Soluble B Vitamin',
    '["tablet"]',
    'Pregnancy prevention of NTD: 500 mcg daily (start before conception and continue first trimester). Folate deficiency: 250–1000 mcg daily.',
    'Generally very well tolerated. High doses (>1 mg/day) may mask B12 deficiency.',
    'Methotrexate (folic acid reduces toxicity — commonly co-prescribed), anticonvulsants (reduced folic acid levels).',
    'Known hypersensitivity.',
    'High-risk women (prior NTD pregnancy, diabetes, anticonvulsant therapy) need 5 mg/day — consult doctor.',
    'Store below 25°C. Protect from light and moisture.',
    'A',
    TRUE, 'ARTG-071234',
    'Unscheduled', 'B03BB01'
),
(
    'Fish Oil 1000mg Capsules',
    'Omega-3 Triglycerides (EPA + DHA)',
    '["Blackmores Fish Oil", "NaturalCare Fish Oil", "Swisse Fish Oil"]',
    'Fish oil 1000 mg providing EPA 180 mg + DHA 120 mg per capsule',
    'Omega-3 Fatty Acid Supplement',
    '["capsule", "softgel"]',
    'General health: 1–2 capsules daily with meals. Elevated triglycerides: 2–4 g/day EPA+DHA (medical supervision).',
    'Fishy aftertaste, burping, GI upset at high doses. High doses may increase bleeding time.',
    'Anticoagulants, antiplatelet drugs (additive bleeding risk with high doses).',
    'Fish or shellfish allergy.',
    'Inform doctor before surgery if taking high doses. Store in fridge after opening to prevent oxidation.',
    'Refrigerate after opening.',
    'A',
    TRUE, 'ARTG-072345',
    'Unscheduled', 'C10AX06'
);

-- ─────────────────────────────────────────────
-- Allergy / Antihistamines
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Cetirizine 10mg Tablets',
    'Cetirizine hydrochloride',
    '["Zyrtec", "Zilarex", "Cetirizine AN"]',
    'Cetirizine hydrochloride 10 mg per tablet',
    'Second-Generation Antihistamine (H1 Antagonist)',
    '["tablet", "syrup"]',
    'Adults and children ≥6 years: 10 mg once daily. Hayfever, urticaria, chronic idiopathic urticaria.',
    'Somnolence (less than first-generation), dry mouth, fatigue, headache.',
    'Alcohol, CNS depressants (additive sedation). Theophylline (decreased cetirizine clearance).',
    'Hypersensitivity to cetirizine or hydroxyzine. Severe renal impairment (eGFR <10 — halve dose).',
    'May cause drowsiness in some — avoid driving if affected.',
    'Store below 30°C.',
    'B2',
    TRUE, 'ARTG-080123',
    'S2', 'R06AE07'
),
(
    'Loratadine 10mg Tablets',
    'Loratadine',
    '["Claratyne", "Lora-Tabs", "Loratadine AN"]',
    'Loratadine 10 mg per tablet',
    'Second-Generation Antihistamine (H1 Antagonist) — Non-Sedating',
    '["tablet", "syrup"]',
    'Adults and children ≥6 years: 10 mg once daily.',
    'Headache, somnolence (rare), dry mouth, fatigue.',
    'Ketoconazole, erythromycin (increased loratadine levels). Alcohol (caution).',
    'Hypersensitivity to loratadine.',
    'Generally considered non-sedating. Safe for daytime use.',
    'Store below 25°C. Protect from moisture.',
    'B1',
    TRUE, 'ARTG-081234',
    'S2', 'R06AX13'
);

-- ─────────────────────────────────────────────
-- Thyroid
-- ─────────────────────────────────────────────
INSERT INTO medicines (name, generic_name, brand_names, composition, drug_class, dosage_forms,
    standard_dosage, side_effects, interactions, contraindications, warnings,
    storage_instructions, pregnancy_category, tga_registered, tga_artg_number,
    schedule, atc_code)
VALUES
(
    'Levothyroxine 50mcg Tablets',
    'Levothyroxine sodium',
    '["Eutroxsig", "Oroxine", "Levothyroxine AN"]',
    'Levothyroxine sodium equivalent to 50 mcg levothyroxine per tablet',
    'Thyroid Hormone Replacement',
    '["tablet"]',
    'Hypothyroidism: Initial 25–50 mcg daily, titrated by TSH every 6–8 weeks. Usual maintenance 100–200 mcg/day.',
    'Signs of hyperthyroidism if overdosed: palpitations, tremor, weight loss, insomnia, diarrhoea.',
    'Calcium, iron, antacids (reduce absorption — separate by ≥4 hours). Warfarin (increased INR). Colestyramine. Certain anticonvulsants.',
    'Untreated adrenal insufficiency. Thyrotoxicosis.',
    'Take 30–60 minutes before food, ideally on empty stomach. Consistent timing daily. Do not switch brands without medical advice.',
    'Store below 25°C. Protect from light and moisture.',
    'A',
    TRUE, 'ARTG-090123',
    'S4', 'H03AA01'
);

-- Update search vectors for all newly inserted medicines
UPDATE medicines SET search_vector =
    setweight(to_tsvector('english', COALESCE(name, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(generic_name, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(drug_class, '')), 'C') ||
    setweight(to_tsvector('english', COALESCE(composition, '')), 'D')
WHERE search_vector IS NULL;

-- Confirm count
DO $$
DECLARE cnt INTEGER;
BEGIN
    SELECT COUNT(*) INTO cnt FROM medicines;
    RAISE NOTICE 'Medicines seed complete. Total rows: %', cnt;
END;
$$;
