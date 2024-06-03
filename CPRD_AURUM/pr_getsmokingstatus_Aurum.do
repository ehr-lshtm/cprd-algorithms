/*********************
*********************
****Modified on 22 April 2020 by Angel Wong
****to take into account those with different smokstatus recorded on the same date/ same _absdistance -> take the worst case (current smoker) first

Label:

0  non-smoker
1  current smoker
2  ex-smoker
9  nonspecified - depends on
   quantity
12  current/ex-smoker

*********************
*********************/
cap prog drop pr_getsmokingstatus_Aurum
program define pr_getsmokingstatus_Aurum

syntax, obsfile(string) icdfile(string) therapyfile(string) smokingstatusvar(string) index(string)



noi di
noi di in yellow _dup(5) "*"
noi di in yellow "Assign smoking status (from clinical codes),"
noi di in yellow "based on nearest status pre index date:"
noi di in yellow _dup(5) "*"


qui{



****************************************************************************************
*GET SMOKING STATUS FROM ICD CODES AND PRESCRIPTIONS FOR NICOTINE REPLACEMENT
****************************************************************************************

preserve
merge 1:m patid using `icdfile', keep(match) nogen
gen eventdate=date(epistart, "DMY")
format eventdate %td
keep patid eventdate `index' `smokingstatusvar'
tempfile icddata
save `icddata'
restore

preserve
merge 1:m patid using `therapyfile', keep(match) nogen
rename issuedate eventdate
keep patid eventdate `index' `smokingstatusvar'
tempfile therapydata
save `therapydata'
restore


****************************************************************************************
*GET SMOKING STATUS FROM CODES, AND SUPPLEMENT WITH QUANTITY FROM OBSERVATION FILE
****************************************************************************************
merge 1:m patid using `obsfile', keep(match master) nogen

* Update smoking status using quantity with unit (per-day) if the codes are not specified (coded as 39)
destring value, replace
replace `smokingstatusvar' = 0 if `smokingstatusvar'== 9 & numunitid == "39" & value == 0
replace `smokingstatusvar' = 1 if `smokingstatusvar'== 9 & numunitid == "39" & value > 0
rename obsdate eventdate

drop if `smokingstatusvar' == 9

keep patid indexdate eventdate `smokingstatusvar' 

append using `icddata'
append using `therapydata'

*********************************************************
*ASSIGN STATUS BASED ON INDEX DATE, USING ALGORITHM BELOW
*********************************************************
*Algorithm:
*Take the nearest status in the period -1y to +1month from index if available (best)
*if not, then take nearest in the period +1month to +1y after index if available(second best)*
*if not, then take any nearest before -1y from index if available (third best)
*if not, then take nearest after +1y from index (least best)

gen _distance = eventdate-`index'
gen _priority = 1 if _distance>=-365 & _distance<=30
replace _priority = 2 if _distance>30 & _distance<=365
replace _priority = 3 if _distance<-365
replace _priority = 4 if _distance>365 & _distance<.
gen _absdistance = abs(_distance)
gen _nonspecific = (`smokingstatusvar'==12)

recode `smokingstatusvar' 0=9 //new
sort patid _priority _absdistance _nonspecific `smokingstatusvar'  //new

*Patients nearest status is non-smoker, but have history of smoking, recode to ex-smoker.
by patid: gen b4=1 if eventdate<=eventdate[1]
drop if b4==.

recode `smokingstatusvar' 9=0 //new
by patid: egen ever_smok=sum(`smokingstatusvar') 
by patid: replace `smokingstatusvar' = 2 if ever_smok>0 & `smokingstatusvar'==0

sort patid _priority _absdistance _nonspecific `smokingstatusvar'  //new
by patid: replace `smokingstatusvar' = `smokingstatusvar'[1] 
drop  _distance _priority _absdistance _nonspecific  
by patid: keep if _n==1

*Recode smoking status as current smoker if not certain whether it's current/former smoker
recode `smokingstatusvar' 12=1

drop b4 ever_smok

}/*end of quietly*/
end
