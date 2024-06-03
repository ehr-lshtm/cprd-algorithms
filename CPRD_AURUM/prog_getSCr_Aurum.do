/*=========================================================================
DO FILE NAME:	prog_getSCr_Aurum

AUTHOR:					Angel Wong (adapted from Kate Mansfield and Helen McDonald's work)

VERSION:				v1.0
DATE VERSION CREATED:	v1 29 Sep 2020					

DESCRIPTION OF FILE: 
	Extracts serum creatinine test results.
	Calculates eGFR
	Optional code to use ethnicity data to calculate eGFR if available
	
	Arguements (options) required:
		* obsfile						// path and name of file containing test result 
										// extract files (exclude the underscore and the number of the file)
		* obsfilesnum 					// number of test files to loop through
		* serum_creatinine_codelist		// list of medcodes that are likely to be used for serum creatinine test results
		* savefile						// string containing name of file to save
		* patientfile					// string containing name of file containing patient details - gender and realyob
		* ethnicityfile  				// optional string with filename of file containing 
										// ethnicity data, ethnicity should be recorded in a var called ethdm

									
HOW TO USE: e.g.

run "J:\EHR-Working\Angel\DOACs\Project_folder\dofiles\programs\prog_getSCr_Aurum.do"

prog_getSCr_Aurum, ///
	obsfile("$pathIn/CPRD_Aurum/Observation_Stata/Observation_append") ///
	obsfilesnum(4) ///
	serum_creatinine_codelist("$pathCodelists/codelist_SCr_cprd_aurum") ///
	savefile("trial-SCr-eGFR") ///
	patientfile("$pathIn/CPRD_Aurum/PatientPracticeStaff/DOACS_Extract_Patient_001")

NB: the optional argument for adding ethnicity has not been tested yet.

*=========================================================================*/


/*******************************************************************************
#>> Define program
*******************************************************************************/
capture program drop prog_getSCr_Aurum
program define prog_getSCr_Aurum

syntax, obsfile(string) obsfilesnum(integer) serum_creatinine_codelist(string) ///
	savefile(string) patientfile(string) ///
	[ethnicityfile(string)]
	
* obsfile			// path and name of file containing test result extract files (exclude the underscore and the number of the file)
* obsfilesnum 		// number of test files to loop through
* serum_creatinine_codelist		// list of medcodes that are likely to be used for serum creatinine test results
* savefile			// string containing name of file to save
* patientfile		// string containing name of file containing patient details - gender and realyob
* ethnicityfile  	// optional string with filename of file containing ethnicity data, ethnicity should be recorded in a var called ethdm

noi di
noi di in yellow _dup(15) "*"
noi di in yellow "Identify serum creatinine test results and calculate eGFR"
noi di in yellow _dup(15) "*"


qui{
/*******************************************************************************
================================================================================
#A. EXTRACT AND CLEAN SCr RESULTS
================================================================================
*******************************************************************************/

	/*******************************************************************************
	#A1. Identify test records for serum creatinine results.
	*******************************************************************************/
	display in red "*******************Observation file number: 1*******************"

	use patid obsdate enterdate value medcodeid numunitid numrangelow numrangehigh using "`obsfile'_1", clear
	merge m:1 medcodeid using "`serum_creatinine_codelist'", keep(match)
	
	save `savefile', replace
	
	

	/*******************************************************************************
	#A2. Loop through subsequent (from 2 onwards) separate test extract files in 
		turn and append the results to the first extract file saved in #1
	*******************************************************************************/
	forvalues n=2/`obsfilesnum' {
		display in red "*******************Observation file number: `n'*******************"

		use patid obsdate enterdate value medcodeid numunitid numrangelow numrangehigh using "`obsfile'_`n'", clear
		merge m:1 medcodeid using "`serum_creatinine_codelist'", keep(match)


		* add the file containing records for the specified comorbidity
		* to make one file containing all specified comorbidiy records for the
		* clinical extract specified
		append using "`savefile'"
		
		* save
		save "`savefile'", replace
	}
	
	
	/*******************************************************************************
	#A3. Drop unnecessary vars and label variables.
	*******************************************************************************/	
	
	*merge m:1 numunitid using "$pathOut\NumUnit", keep(master match) nogen
	
	destring value, gen(SCr)
	 
	*rename variables and add labels
	rename numunitid    unit 			// unit of measure
	rename numrangelow  rangeFrom 	//"normal range from"
	rename numrangehigh rangeTo		//"normal range to"
	
	label variable SCr "SCr: SCr result"
	label variable unit "unit of measure"	
	label variable rangeFrom "rangeFrom: normal range from"
	label variable rangeTo "rangeTo: normal range to"	
	
	/*******************************************************************************
	#A4. Drop any duplicate records
		Drop records with missing dates or SCr results
	*******************************************************************************/	
	duplicates drop

	* drop if eventdate missing 
	* but check if sysdate available and replace missing eventdate with sysdate if available
	replace obsdate=enterdate if (obsdate==. & enterdate!=.)
	drop if obsdate==.
	
	* drop if creatinine value is missing or zero
	drop if SCr==0 
	drop if SCr==.

	
	
	/*******************************************************************************
	#A6. Drop records with SCr values that are very low or very high
	*******************************************************************************/
	* drop improbable values for SCr i.e. <20 or >3000
	gen improbable=0
	recode improbable 0=1 if SCr<20 | SCr>3000

	drop if improbable==1
	drop improbable	
	
	
	
	
	/*******************************************************************************
	#A7. Add notes and labels to the data
	*******************************************************************************/
	notes: prog_getSCr.do / TS
	save "`savefile'", replace

	
	
	
/*******************************************************************************
================================================================================
#B. CALCULATE eGFR
================================================================================
*******************************************************************************/
	/**************************************************************************
	#B1. Open patient details file, sort and save relevant details ready to merge
		with test results file
	**************************************************************************/
	use patid gender yob using "`patientfile'", clear
	
	destring gender, replace
	destring yob, replace
	
	sort patid
	
	merge 1:m patid using "`savefile'", nogen keep(match) force // only keep patients with test results available
	
	
	/**************************************************************************
	#B2. Calculate age at event
	**************************************************************************/	
	generate eventyr = year(obsdate)
	count if eventyr==yob /*22*/
	drop if eventyr==yob // drop if test result is in the same year as patient born

	* make an age at event
	gen ageAtEvent=0
	replace ageAtEvent=eventyr - yob - 1 if obsdate<mdy(07,01,eventyr) // round down if eventdate in first half of year
	replace ageAtEvent=eventyr - yob if obsdate>=mdy(07,01,eventyr)	

	
	
	/**************************************************************************
	#B3. Deal with duplicate records
	**************************************************************************/
	*drop enterdate and medcodeid so the only same day duplicates are those with different values for data2
	drop enterdate medcodeid 
	duplicates drop

	
	
	/**************************************************************************
	#B4. Calculate eGFR
	**************************************************************************/
	* calculate egfr using ckd-epi
	* first multiply by 0.95 (for assay - fudge factor) and divide by 88.4 (to convert umol/l to mg/dl)
	* DN "fudge factor"
	gen SCr_adj=(SCr*0.95)/88.4

	gen min=.
	replace min=SCr_adj/0.7 if gender==2
	replace min=SCr_adj/0.9 if gender==1
	replace min=min^-0.329 if gender==2
	replace min=min^-0.411 if gender==1
	replace min=1 if min<1

	gen max=.
	replace max=SCr_adj/0.7 if gender==2
	replace max=SCr_adj/0.9 if gender==1
	replace max=max^-1.209
	replace max=1 if max>1

	gen egfr=min*max*141
	replace egfr=egfr*(0.993^ageAtEvent)
	replace egfr=egfr*1.018 if gender==2
	label var egfr "egfr calculated using CKD-EPI formula with no eth + fudge"
	
	* categorise into ckd stages
	egen egfr_cat= cut(egfr), at(0, 15, 30, 45, 60, 5000)
	label define EGFR 0"stage 5" 15"stage 4" 30"stage 3b" 45"stage 3a" 60"no CKD"
	label values egfr_cat EGFR
	label var egfr_cat "eGFR category calc without eth + DN fudge factor"
	
	* * recode with appropriate category as reference
	recode egfr_cat 0=5 15=4 30=3 45=2 60=0, generate(ckd)
	label define ckd 0"no CKD" 2"stage 3a" 3"stage 3b" 4"stage 4" 5"stage 5"
	label values ckd ckd
	label var ckd "CKD stage calc without eth + DN fudge factor"
	
	/*
	CKD STAGES
		stage 2 and below: eGFR >=60
		stage 3a: eGFR 45-59
		stage 3b: eGFR 30-44
		stage 4: eGFR 15-29
		stage 5: eGFR <15)

	Low eGRF = bad
	High eGFR = good
	*/
	
	if "`ethnicityfile'"!="" {
		* use ethnicity to calculate eGFR if the ethnicityfile option is
		* specified
		merge 1:1 patid using "`ethnicityfile'", keep(match master) nogen keepusing(ethdm)
		generate egfr_eth=egfr*1.159 if ethdm==2	// recalculate egfr for those with black ethnicity
		replace egfr_eth=egfr if ethdm!=2 & ethdm!=. & ethdm!=5	// set this variable to previous value if ethnicity other than black and ethnicity not either missing or not stated
		label var egfr_eth "egfr calculated using CKD-EPI formula with ethnicity"
	
		* categorise into ckd stages
		egen egfr_cat_eth= cut(egfr_eth), at(0, 15, 30, 45, 60, 5000)
		label values egfr_cat_eth EGFR
		label var egfr_cat_eth "eGFR category calc with ethnicity"
		
		* recode with appropriate category as reference
		recode egfr_cat_eth 0=5 15=4 30=3 45=2 60=0, generate(ckd_eth)
		label values ckd_eth ckd
		label var ckd_eth "CKD stage calculated with ethnicity"
	}


	* save	
	label data "serum creatinine records and eGFR results from CPRD"
	notes: prog_getScr.do / TS
	save "`savefile'", replace

}/*end of quietly*/

end


