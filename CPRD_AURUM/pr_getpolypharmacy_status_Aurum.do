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

cap prog drop pr_getpolypharmacy_status_Aurum
program define pr_getpolypharmacy_status_Aurum

syntax, cohortfile(string) savefile(string)

qui {
	
/*********************************************************************
*1. Identify number of drugs using BNF chapters 
*********************************************************************/
sort patid
bysort patid: egen num_rx_main = total(main_analysis_for_counting)
bysort patid: egen num_rx_sens = total(sens_analysis_for_counting)

* Create variables for polypharmacy
duplicates drop patid, force

save "temp_counting_rx", replace

/*********************************************************************
*2. Identify polypharmacy in specific cohort 
*********************************************************************/
use "`cohortfile'", clear
merge 1:1 patid using "temp_counting_rx", ///
	keepusing(num_rx_main num_rx_sens) keep(master match) nogen

replace num_rx_main = 0 if num_rx_main == .
replace num_rx_sens = 0 if num_rx_main == .

* Polypharmacy flag in main analysis
gen polypharmacy_main = 1 if num_rx_main >= 5
replace polypharmacy_main = 0 if num_rx_main < 5

label var polypharmacy_main "polypharmacy (>=5 drugs) using BNF chapter without counting topical Rx"

* Degree of polypharmacy flag in main analysis
gen polypharmacy_degree_main = 0 if num_rx_main == 0
replace polypharmacy_degree_main = 1 if num_rx_main >= 1 & num_rx_main <= 4 
replace polypharmacy_degree_main = 2 if num_rx_main >= 5 & num_rx_main <= 9
replace polypharmacy_degree_main = 3 if num_rx_main >= 10 

label var polypharmacy_degree_main "Polypharmacy degree without counting topical Rx"
label def polypharmacy_lbl 0 "0" 1 "1-4" 2 "5-9" 3 ">=10"
label val polypharmacy_degree_main polypharmacy_lbl

* Polypharmacy flag in sensitivity analysis
gen polypharmacy_sens = 1 if num_rx_sens >= 5
replace polypharmacy_sens = 0 if num_rx_sens < 5

label var polypharmacy_sens "polypharmacy (>=5 drugs) using BNF chapter including topical Rx"

* Degree of polypharmacy flag in sensitivity analysis
gen polypharmacy_degree_sens = 0 if num_rx_sens == 0
replace polypharmacy_degree_sens = 1 if num_rx_sens >= 1 & num_rx_sens <= 4 
replace polypharmacy_degree_sens = 2 if num_rx_sens >= 5 & num_rx_sens <= 9
replace polypharmacy_degree_sens = 3 if num_rx_sens >= 10 

label var polypharmacy_degree_sens "Polypharmacy degree including topical Rx"
label val polypharmacy_degree_sens polypharmacy_lbl

keep patid indexdate num_rx_main num_rx_sens polypharmacy_main polypharmacy_sens ///
polypharmacy_degree_main polypharmacy_degree_sens

save "`savefile'", replace

erase "temp_counting_rx.dta"

}
end
