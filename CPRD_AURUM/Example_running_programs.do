*Created by Angel Wong
*Example of running the programs
*patid = patient identified
*indexdate = set by researcher - cohort entry
/*******************************************************************************
Set memory and run programs
*******************************************************************************/
clear all

set max_memory 130g

run "$pathPrograms/pr_getsmokingstatus_Aurum.do"
run "$pathPrograms/pr_getalcoholstatus_Aurum.do"
run "$pathPrograms/pr_getallbmirecords_Aurum.do"
run "$pathPrograms/pr_getbmistatus_Aurum.do"
run "$pathPrograms/pr_getbloodpressure_Aurum.do"
run "$pathPrograms/pr_getbp_Aurum_cohort.do"
run "$pathPrograms/pr_getallbmirecords_Aurum.do"

/*******************************************************************************
import Numunit dataset again
*******************************************************************************/

import delimited using "NumUnit.txt", clear stringcols(_all)  //lookup files
save "$pathOut/NumUnit", replace


use "J:\EHR Share\3 Database guidelines and info\CPRD Aurum\Denominator files\2022_05\202205_CPRDAurum_AllPats", clear //denominator file
tostring yob, replace
keep patid yob
save "$pathOut/202205_CPRDAurum_AllPats", replace

/*******************************************************************************
* Extract individual drug data from the drug issue append file
*******************************************************************************/
foreach i in Nicotine_replacement Antabuse {
  forval num = 1/13 {
use patid issuedate prodcodeid using "DrugIssue_append_`num'", clear
merge m:1 prodcodeid using "$pathCodelistsNew/`i'_aurum", keep(match) keepusing(prodcodeid) nogen
save "$pathOut/aurum_`i'_`num'", replace
 }
 }

  foreach i in Nicotine_replacement Antabuse {
 	use "$pathOut/aurum_`i'_1", clear 
  forval num = 2/13 {
	append using "$pathOut/aurum_`i'_`num'"
 }
 	save "$pathOut/aurum_`i'_all", replace
				}
 

foreach i in Nicotine_replacement Antabuse {
		forval num = 1/13 {
	erase "$pathOut/aurum_`i'_`num'.dta"
	}
 }
/*******************************************************************************
#1. Extract all relevant files for identifying smoking status
and identify the smoking status at the index date
*******************************************************************************/
*Get all records from Observation file
forval i=1/23 {
use patid obsdate numunitid value medcodeid using "${pathIn}/Observation/Observation_append_`i'", clear
merge m:1 medcodeid using "$pathCodelistsNew/codelist_smoking_cprd_aurum", keep(match) keepusing(smokstatus) nogen
save "Obs_smoking_`i'", replace 
}
use "Obs_smoking_1", clear
forval i=2/23 {
append using "Obs_smoking_`i'"
}
save "Obs_smoking_all_update", replace

* Smoking cessation
*extracted above

*Get all records in HES indicating smoking status
use "$pathAulink/hes_diagnosis_epi_23_002786_DM", clear
merge m:1 icd using "$pathCodelists/Smoking_ICD", keep(match) nogen
save "hes_ICD_Smoking_Aurum.dta", replace

use "$pathOut/aurum_Nicotine_replacement_all", clear
merge m:1 prodcodeid using "$pathCodelistsNew/Nicotine_replacement_aurum", keep(match) keepusing(smokstatus) nogen
save "$pathOut/aurum_Nicotine_replacement_all", replace


 use "$pathOut/aurum_final_2019", clear //your cohort input
 keep patid indexdate
 noi pr_getsmokingstatus_Aurum, obsfile(Obs_smoking_all_update) ///
 icdfile(hes_ICD_Smoking_Aurum.dta) therapyfile("$pathOut/aurum_Nicotine_replacement_all") ///
 smokingstatusvar(smokstatus) index(indexdate)
 save "$pathOut/aurum_smoke_update", replace

/*******************************************************************************
#2. Extract all relevant files for identifying alcohol consumption
and identify the alcohol consumption status at the index date
*******************************************************************************/
*Get all records from Observation file
forval i=1/23 {
use patid obsdate medcodeid numunitid medcodeid value using "${pathIn}/Observation/Observation_append_`i'", clear
merge m:1 medcodeid using "$pathCodelistsNew/codelist_alcohol_cprd_aurum", keep(match) nogen
save "Obs_alc_`i'", replace 
}
use "Obs_alc_1", clear
forval i=2/23 {
append using "Obs_alc_`i'"
}
save "Obs_alc_all_update", replace

*Get all records in HES indicating alcohol status
use "$pathAulink/hes_diagnosis_epi_23_002786_DM", clear
merge m:1 icd using "$pathCodelists/FromAceiproj/Alcohol_ICD", keep(match) nogen
gen eventdate=date(epistart, "DMY")
format eventdate %td
drop epistart
rename eventdate epistart
save "hes_ICD_Alcohol_Aurum.dta", replace

/*Get all records in CPRD Aurum indicating antabuse treatment
*extracted from above*/
use "$pathOut/aurum_Antabuse_all", clear
merge m:1 prodcodeid using "$pathCodelistsNew/Antabuse_aurum", keep(match) keepusing(alcstatus alclevel) nogen
save "$pathOut/aurum_Antabuse_all", replace
    
 use "$pathOut/aurum_final_2019", clear //your cohort input
 keep patid indexdate
 run "$pathPrograms/pr_getalcoholstatus_Aurum"
 noi pr_getalcoholstatus, obsfile("Obs_alc_all_update") ///
 numunitfile("$pathCodelists/alcohol_level_aurum")  ///
 icdfile("hes_ICD_Alcohol_Aurum") therapyfile("$pathOut/aurum_Antabuse_all") ///
 alcoholstatusvar(alcstatus) alcohollevelvar(alclevel) ///
 unit_time(unit_time) index(indexdate)
 save "$pathOut/aurum_alc_update", replace

/*******************************************************************************
#3. Extract all relevant files for identifying body mass index & body weight
and identify the BMI status and weight at the index date
*******************************************************************************/
*Get all records from Observation file
forval i=1/23 {
use patid medcodeid value obsdate numunitid using "${pathIn}/Observation/Observation_append_`i'", clear
merge m:1 medcodeid using "$pathCodelistsNew/bmi_codes_aurum.dta", keep(match) nogen
save "Obs_bmi_`i'", replace 
}
use "Obs_bmi_1", clear
forval i=2/23 {
append using "Obs_bmi_`i'"
}
save "Obs_bmi_all_update", replace

/**************
* BMI status
**************/
    
 use "$pathOut/aurum_final_2019", clear //your cohort input
 keep patid indexdate
 noi pr_getbmistatus_Aurum, obsfile("Obs_bmi_all_update") ///
 patientfile("$pathOut/202205_CPRDAurum_AllPats") ///
 numunitfile("$pathOut/NumUnit") index(indexdate)
 save "$pathOut/aurum_final_bmi", replace


/*******************************************************************************
#4. Extract all relevant files for identifying blood pressure
*******************************************************************************/

pr_getbloodpressure_Aurum, ///
 obsfile("${pathIn}/Observation/Observation_append") ///
 obsfilesnum(23)  ///
 bp_codelist("$pathCodelistsNew/specific_bp_codes_aurum") ///
 savefile("Aurum_bp_all_update")

/*******************************************************************************
#5. Extract all relevant files for identifying polypharmacy
*******************************************************************************/
run "$pathPrograms/pr_getpolypharmacy_records_Aurum"

noi pr_getpolypharmacy_records_Aurum, drugdictionary("$pathBrowsersAurum22/CPRDAurumProduct.txt") ///
 cohortfile("$pathOut/aurum_final_2019") ///
 drugfile("DrugIssue_append") ///
 drugfilepart("Z:/GPRD_GOLD/Angel/DOAC_interactions/Updated_data/drug_append") ///
 drugfilesnum(13) lookbackwindow(90) savefile("$pathOut/aurum_polypharmacy_record") ///
 index(indexdate)

*obtain polypharmacy status
run "$pathPrograms/pr_getpolypharmacy_status_Aurum"
	
	use "$pathOut/aurum_polypharmacy_record", clear
noi pr_getpolypharmacy_status_Aurum, cohortfile("$pathOut/aurum_final_2019") ///
 savefile("$pathOut/aurum_final_polypharmacy") 
 
 
/*******************************************************************************
#6. Extract all serum creatinine records and eGFR status
*******************************************************************************/
 
 prog_getSCr_Aurum, ///
	obsfile("${pathIn}/Observation/Observation_append") ///
	obsfilesnum(16) ///
	serum_creatinine_codelist("$pathCodelistsNew/codelist_SCr_cprd_aurum") ///
	savefile("$pathOut/SCr-eGFR-result_aurum") ///
	patientfile("$pathIn/Patient_append")
