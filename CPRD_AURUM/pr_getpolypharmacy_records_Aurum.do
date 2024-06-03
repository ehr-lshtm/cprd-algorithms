/*=========================================================================
AUTHOR:					Angel Wong		
VERSION:				v1
DATE VERSION CREATED:	2021-06-11

DESCRIPTION OF FILE: identify polypharmacy for drug-drug interaction project

OVERALL AIM: 

We are going to be studying specific drugs that might interact with DOACs. 
Within each analysis we also want to have a variable that identifies people with polypharmacy 
to see if they are more likely to have any of these specific drug interactions with DOAC. 
There are lots of ways we could approach this, but to be pragmatic the idea is to exclude things 
that are not relevant for drug interactions. 
Things like dressings are obviously excluded and oral meds are obviously included. 
The topicals seem debatable, therefore a sensitivity analysis where they’re included
		
MORE INFORMATION:

1. Defined as >=5 different drugs prescribed with a certain number of days before index date
2. Use BNF chapters to count number of drugs (If use drug name/productcode - may overcount due to drug switching
3. From Aurum dictionary, no drug were assigned as BNF chapter > 15

Steps:

NB: 
Remove drugs which do not have valid BNF chapters
For those wth termfromemis/drugsubstancename/productname that contains substring like: 
	"stocking"
	"dressing"
	"appliance"
	Most of them have missing BNF chapters in Aurum dictionary
	
TO RUN THIS PROGRAM:

*=========================================================================*/

cap prog drop pr_getpolypharmacy_records_Aurum
program define pr_getpolypharmacy_records_Aurum

syntax, index(string) drugdictionary(string) cohortfile(string) ///
 drugfile(string) drugfilepart(string) drugfilesnum(integer) lookbackwindow(integer) ///
 savefile(string)

qui {
	

/*******************************************************************************
1 a. Identify drug records from first drug file and save to append subsequent files to.
*******************************************************************************/
import delimited using "`drugdictionary'", clear stringcols(_all) delimit(tab)

*Make all descriptions lower case
foreach var of varlist termfromemis productname drugsubstancename routeofadministration substancestrength formulation {
gen Z=lower(`var')
drop `var'
rename Z `var'
}

save "CPRD_Aurum_Product_Browser", replace

preserve
keep if !missing(drugsubstancename) & !missing(bnfchapter)
duplicates drop drugsubstancename, force
save "unique_druglist", replace
restore

keep if missing(bnfchapter)
drop bnfchapter
merge m:1 drugsubstancename using "unique_druglist", keepusing(bnfchapter) keep(master match) nogen
tempfile miss_bnf
save `miss_bnf'

use "CPRD_Aurum_Product_Browser", clear
keep if !missing(bnfchapter)
append using `miss_bnf'

save "CPRD_Aurum_Product_Browser_v2", replace

	/*******************************************************************************
	a. Identify drug records from first drug file and save to append subsequent files to.
	*******************************************************************************/
	use patid prodcodeid issuedate using "`drugfilepart'/`drugfile'_1", clear
	merge m:1 patid using "`cohortfile'", keepusing(`index') keep(match) nogen 
	keep if issuedate != . & issuedate >= `index' - `lookbackwindow' & issuedate <= `index'
	save "au_temp_savefile", replace

	display in red "*******************Drug file number: 1*******************"

	/*******************************************************************************
	b. Loop through subsequent (from 2 onwards) separate drug extract files in 
		turn and append the results to the first extract file saved in #1
	*******************************************************************************/
	if `drugfilesnum'>1 {
		forvalues n=2/`drugfilesnum' {
			display in red "*******************Drug file number: `n'*******************"

			use patid prodcodeid issuedate using "`drugfilepart'/`drugfile'_`n'", clear
			merge m:1 patid using "`cohortfile'", keepusing(`index') keep(match) nogen
			keep if issuedate != . & issuedate >= `index' - `lookbackwindow' & issuedate <= `index'
			
			append using "au_temp_savefile"
			
			save "au_temp_savefile", replace
		}
	} /*end if `clinicalfilesnum'!=1*/
	
	/*******************************************************************************
	c. Add notes and labels to the data
	*******************************************************************************/	
	label data "Drug records data (`lookbackwindow' days before index date) from CPRD"
	compress
	
	* Rename date variable for Aurum
	rename issuedate eventdate
	
	save "au_temp_savefile", replace

/*********************************************************************
*2. Flag BNF chapters which should be excluded in the main analysis 
NB: Tabulate all the BNF chapter from Aurum dictionary and found these have finer subchapter within each subchapter
Subgroup within 131001 and 130201 -
"13100101" 
"13100102"
"13020101" 
*********************************************************************/
merge m:1 prodcodeid using "CPRD_Aurum_Product_Browser_v2", ///
	keepusing(bnfchapter routeofadministration termfromemis productname drugsubstancename) ///
	keep(master match) nogen

* Remove those with missing BNF chapter
count if missing(bnfchapter)
drop if missing(bnfchapter)

* Remove duplicates within same BNF chapter
duplicates drop patid bnfchapter, force

* Main analysis
gen main_remove_bnf = .

#delimit ;
loc mainexterm "
"1070000"
"1070100"
"1070200"
"1070300"
"1070400"
"1080000"
"1080100"
"7020100"
"10030000"
"10030100"
"10030200"
"11000000"
"11030000"
"11030100"
"11030200"
"11030300"
"11040100"
"11050000"
"11060000"
"11070000"
"11080000"
"11080100"
"11080200"
"11080300"
"12000000"
"12010000"
"12010100"
"12010300"
"12020000"
"12020100"
"12020200"
"12020300"
"12030100"
"12030200"
"12030300"
"12030400"
"12030500"
"13010000"
"13010100"
"13020000"
"13020100"
"13020101" 
"13020200"
"13020300"
"13030000"
"13040000"
"13050000"
"13050100"
"13050200"
"13060100"
"13060300"
"13070000"
"13080000"
"13080100"
"13080200"
"13090000"
"13100000"
"13100100"
"13100101" 
"13100102" 
"13100200"
"13100300"
"13100400"
"13100500"
"13110000"
"13110100"
"13110200"
"13110300"
"13110400"
"13110500"
"13110600"
"13110700"
"13120000"
"13130000"
"13130100"
"13130800"
"13140000"
"13150000"
";
#delimit cr

* Update the marker where BNF matches above ones
foreach word of local mainexterm {
	di "`word': "
	replace main_remove_bnf = 1 if !missing(bnfchapter) & bnfchapter == "`word'"
}

* Exclusion due to dressing/stocking/appliance

gen main_exclude_term = .

#delimit ;
loc exclterm "
"stocking"
"dressing"
"appliance"
";
#delimit cr

* Update the marker where drug/product name matches search terms
foreach word of local exclterm {
	di "`word': "
	replace main_exclude_term = 1 if regexm(termfromemis, "`word'")
	replace main_exclude_term = 1 if regexm(productname, "`word'")
	replace main_exclude_term = 1 if regexm(drugsubstancename, "`word'")
}

gen route = .

* Include some back according to routeofadministration
#delimit ;
loc route "
"buccal"
"nasal"
"oral"
"oromucosal"
"inhalation"
"intramuscular"
"intravenous"
"subcutaneous"
"intrathecal"
"nasal"
"submucosal rectal"
";
#delimit cr

* Update the marker where routeofadministration matches terms
foreach word of local route {
	di "`word': "
	replace route = 1 if regexm(termfromemis, "`word'")
	replace route = 1 if regexm(productname, "`word'")
	replace route = 1 if regexm(drugsubstancename, "`word'")
	replace route = 1 if regexm(routeofadministration, "`word'")
}

gen main_analysis_for_counting = 0 		if main_remove_bnf == 1
replace main_analysis_for_counting = 0  if main_exclude_term == 1
replace main_analysis_for_counting = 1  if route == 1
replace main_analysis_for_counting = 1  if main_analysis_for_counting == .

drop main_remove_bnf main_exclude_term route

/*********************************************************************
*3. Flag BNF chapters which should be included in the sensitivity analysis
*********************************************************************/
gen sens_remove_bnf = .

#delimit ;
loc sensexterm "
"13080200"
"13130100"
"13130800"
";
#delimit cr

*** update the marker where read term matches search terms
foreach word of local sensexterm {
	di "`word': "
	replace sens_remove_bnf = 1 if bnfchapter == "`word'"
}

// For those drugs with above BNF chapters, all with missing routeofadministration
 
* Exclusion due to dressing/stocking/appliance

gen sens_exclude_term = .

#delimit ;
loc exclterm "
"stocking"
"dressing"
"appliance"
";
#delimit cr

* Update the marker where drug/product name matches search terms
foreach word of local exclterm {
	di "`word': "
	replace sens_exclude_term = 1 if regexm(termfromemis, "`word'")
	replace sens_exclude_term = 1 if regexm(productname, "`word'")
	replace sens_exclude_term = 1 if regexm(drugsubstancename, "`word'")
}

gen sens_analysis_for_counting = 0 		if sens_remove_bnf == 1
replace sens_analysis_for_counting = 0  if sens_exclude_term == 1
replace sens_analysis_for_counting = 1  if sens_analysis_for_counting == .

drop sens_remove_bnf sens_exclude_term

save "`savefile'", replace

erase "CPRD_Aurum_Product_Browser.dta"
erase "CPRD_Aurum_Product_Browser_v2.dta"
erase "unique_druglist.dta"
erase "au_temp_savefile.dta"

}
end
