/*=========================================================================
DO FILE NAME:	    pr_getbloodpressure_Aurum

AUTHOR:				Angel Wong (adapted some codes from Sarah-Jo)

DESCRIPTION OF FILE: 
Using observation files to get BP measurements	

Note:
1. Remove out of range values
2. Use parentobsid to link SBP and DBP
3. For those without parentobsid, use obsdate to link SBP and DBP
4. Remove records with missing date for both SBP and DBP for each entry
5. Take the smallest value if multiple records on the same date
*=========================================================================*/
	
capture program drop pr_getbloodpressure_Aurum
program define pr_getbloodpressure_Aurum

syntax, obsfile(string) obsfilesnum(integer) bp_codelist(string) ///
	savefile(string)
	
* obsfile			// path and name of file containing test result extract files (exclude the underscore and the number of the file)
* obsfilesnum 		// number of test files to loop through
* bp_codelist		// list of medcodes that are used for identifying SBP and DBP
* savefile			// string containing name of file to save


noi di
noi di in yellow _dup(15) "*"
noi di in yellow "Identify Blood pressure (SBP and DBP)"
noi di in yellow _dup(15) "*"


qui{
/*******************************************************************************
================================================================================
1. EXTRACT BP RECORDS
================================================================================
*******************************************************************************/

	/*******************************************************************************
	#A1. Identify records for blood pressure.
	*******************************************************************************/
	display in red "*******************Observation file number: 1*******************"

	use patid medcodeid value parentobsid obsdate using "`obsfile'_1", clear
	merge m:1 medcodeid using "`bp_codelist'", ///
	keep(match) keepusing(medcodeid bptype) nogen
	
	save `savefile', replace
	
	

	/*******************************************************************************
	#A2. Loop through subsequent (from 2 onwards) separate test extract files in 
		turn and append the results to the first extract file saved in #1
	*******************************************************************************/
	forvalues n=2/`obsfilesnum' {
		display in red "*******************Observation file number: `n'*******************"

		use patid medcodeid value parentobsid obsdate using "`obsfile'_`n'", clear
		merge m:1 medcodeid using "`bp_codelist'", ///
		keep(match) keepusing(medcodeid bptype) nogen

		append using "`savefile'"

		* save
		save "`savefile'", replace
	}
	
	
*********************************************************************************
*2. Restructure dataset to link SBP and DBP*
********************************************************************************* 
	destring value, replace
	
	* create a new unique ID for those missing parentobsid
	gen double nid = _n
	tostring nid, replace
	
	capture {
	* assert if nid is distinct
	duplicates tag nid, generate(dup_check)
	assert dup_check == 0 
	}
	
	if _rc!=0 {
	noi display in red "*******************Not Completed**************************"
	noi display in red "*******************Program ended**************************"
	noi display in red "*******************Too many observations*******************"
	noi display in red "*******************Need program fix************************"
	}
	
	replace parentobsid = "miss" + nid if missing(parentobsid)
	drop dup_check nid
	
	save "`savefile'", replace
	
	************************************
	* Identify records for Systolic BP
	************************************
	keep if bptype == 1

	rename obsdate sys_date
	rename value sys_value
	
	************************************
	*Deal with out of range vals
	***********************************
	replace sys_value = . if sys_value != . &  (sys_value>=240 | sys_value<40) 	
	//out of range vals for sys_bp ==  >=240 and <40. BMJ 2000 Adler higher end is 230
	
	* keep the lowest SBP if having same parentobsid sys_date 
	sort patid parentobsid sys_date sys_value
	by patid parentobsid sys_date: keep if _n==1
		
	keep patid medcodeid sys_value parentobsid sys_date
	
	* create a temp file to save obsid linked SBP
	tempfile systolic_bp
	save `systolic_bp'
	
	* keep the lowest SBP if having same sys_date 
	sort patid sys_date sys_value
	by patid sys_date: keep if _n==1
	
	rename sys_value sys_value_new
	rename sys_date eventdate
	
	* create a temp file to save date linked SBP
	tempfile systolic_bp_date
	save `systolic_bp_date'
		
	************************************
	*Identify records for Diastolic BP
	************************************
	use "`savefile'", clear
	keep if bptype == 2
		
	rename obsdate dia_date
	rename value dia_value
	
	************************************
	*Deal with out of range vals
	***********************************
	replace dia_value = . if dia_value != . &  (dia_value<30  | dia_value>=201) 
	//out of range vals for dia_bp ==  >=201 and <30 
	
	* keep the lowest DBP if having same parentobsid dia_date 
	sort patid parentobsid dia_date dia_value
	by patid parentobsid dia_date: keep if _n==1
		
	keep patid medcodeid dia_value parentobsid dia_date
	
	* create a temp file to save obsid linked DBP
	tempfile diastolic_bp
	save `diastolic_bp'
		
	* keep the lowest DBP if having same dia_date 
	sort patid dia_date dia_value	
	by patid dia_date: keep if _n==1
	
	rename dia_value dia_value_new
	rename dia_date eventdate

	* create a temp file to save date linked DBP
	tempfile diastolic_bp_date
	save `diastolic_bp_date'
	
	************************************
	* Merge SBP and DBP using parentobsid
	************************************
	use `systolic_bp', clear
		
	merge 1:1 patid parentobsid using `diastolic_bp', ///
	keepusing(dia_value dia_date)
	
	clonevar eventdate = sys_date
	
	*Remove records that had missing date recorded
	drop if (sys_date == . | dia_date == .) & _merge == 3
	
	*Remove records that had same observation id but different date recorded for SBP and DBP
	drop if (sys_date != dia_date) & _merge == 3

	************************************
	* Merge SBP and DBP using date
	************************************
	merge m:1 patid eventdate using `diastolic_bp_date', ///
	keepusing(dia_value_new) nogen
	
	replace dia_value = dia_value_new if _merge == 1
	
	merge m:1 patid eventdate using `systolic_bp_date', ///
	keepusing(sys_value_new) nogen
	
	replace sys_value = sys_value_new if _merge == 2
	
	drop _merge
		
*********************************************************************************
*2. Cleaning BP data*
********************************************************************************* 
	keep patid dia_value dia_date sys_value parentobsid sys_date
	
	*Rename date of SBP and DBP
	drop dia_date
	rename sys_date eventdate
	
    * remove records without any diastolic or systolic BP
	drop if dia_value == . & sys_value == .        

************************************
*Dealing with more than one measurement on one day: take the smallest one
************************************
	* sort data so that lowest dia and sys occur first for each id eventdate group
	bysort patid eventdate (sys_value dia_value) : gen lowest = sys_value[1] 		

	* sort data so that lowest dia and sys occur first for each id eventdate group
	bysort patid eventdate (dia_value sys_value) : gen lowest_d = dia_value[1] 		

	* create an indicator to id the only observation in each id eventdate group
	egen tag = tag(patid eventdate) 
	by patid eventdate : replace sys_value=lowest 
	by patid eventdate : replace dia_value=lowest_d 

	* remove duplicate in patid eventdate group
	drop if tag==0

	keep patid eventdate sys_value dia_value
	
	order eventdate, after(patid)
	
	rename dia_value diastolic_bp
	rename sys_value systolic_bp 
	
	label var diastolic_bp "diastolic blood pressure measurement"
	label var systolic_bp "systolic blood pressure measurement"
	label var eventdate "Date of blood pressure recorded"

	save "`savefile'", replace

}/*end of quietly*/

end
