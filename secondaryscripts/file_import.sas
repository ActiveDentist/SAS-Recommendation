
/* Load Dataset*/
proc import datafile="/folders/myfolders/KNN/Data/ratings.dat.003" 
			out=reco.t_mydata3   
			dbms=dlm    
			replace;
				delimiter='::';
 				getnames=no;
run;

/*  Join table parts */
Proc sql;
create table reco._base_1m as
SELECT *
FROM  reco.t_mydata

UNION

(SELECT *
FROM reco.t_mydata2

UNION

SELECT *
FROM reco.t_mydata3);

quit;


/* Drop empty columns */
proc sql;
ALTER TABLE reco.t_mydata3
DROP COLUMN VAR6;
quit;


/* Rename columns */
proc datasets library=reco nolist;
modify _base_1m;
rename VAR1 = UserId;
rename VAR3 = ItemId;
rename VAR5 = Rating;
rename VAR7 = Timestamp;
quit;