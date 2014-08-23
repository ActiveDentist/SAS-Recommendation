/*Data directory specification*/ 
LIBNAME rcm '/folders/myfolders/KNN/Data' ;

%let InDS= rcm._base_1m;   	/*Used DataSet*/
%let RandomSeed = 984;		/*Random seed: dividing into T&L Parts*/


/******************************************************************/
/**********************Recommendation******************************/
/******************************************************************/

/*Divide BaseTable into L (80%) & T(20%) parts*/
data rcm.A_SampleTable;
set &InDS;
call streaminit(&RandomSeed); /* set random number seed */
   u = rand("Uniform"); /* u ~ U[0,1] */
   if U <=0.8 then 
   Part = "L" ;
   else
   Part = "T";
run;

/* Item AVG */
proc sql;
create table rcm.A_AVG_ItemID as 
select ItemID, avg (Rating) as AvgRatingOnItem
from rcm.A_SampleTable 
where Part = "L" group by ItemID;
quit;

/* User AVG */
proc sql;
create table rcm.A_AVG_UserID as 
select UserID, avg (Rating) as AvgRatingOnUser
from rcm.A_SampleTable 
where Part = "L" group by UserID;
quit;

/* global AVG Rating to variable*/
Title3 "AVG DataSet Rating";
proc sql;
SELECT AVG(Rating) 
Into: AvgRating 
FROM rcm.A_SampleTable 
where Part = "L";
quit;







/*Join AVGs Raging by User & Item*/
proc sql;
create table rcm.A_DataSetPredicted as
Select 
t1.UserID, 
t1.ItemID, 
Rating, 
Part, 
AvgRatingOnItem, 
AvgRatingOnUser,
AvgRatingOnItem + (AvgRatingOnUser - &AvgRating) as RcmRating
From rcm.A_SampleTable t1
LEFT JOIN rcm.A_AVG_ItemID t2
ON t1.ItemID=t2.ItemID
Left join rcm.A_AVG_UserID t3
on t1.UserID=t3.UserID;
quit;

/* replace missing values: globalAVG */
proc stdize 
	data=rcm.A_DataSetPredicted
	reponly missing=&AvgRating 
	out=rcm.A_DataSetPredicted;
var _numeric_;
run;


/*Max & Min Ratings*/
Title3 "Max Rating";
Proc sql;
select max(rating)
into: MaxRating
from &InDS;
quit;
Title3 "Min Rating";
Proc sql;
select min(rating)
into: MinRating
from &InDS;
quit;

/*** Bound to limits v 2***/
data rcm.A_DataSetPredicted_adv;
set rcm.A_DataSetPredicted ;
    PredRatingBounded=	min(max(RcmRating, &MinRating ),&MaxRating);
    SqDiff = (PredRatingBounded- Rating)*(PredRatingBounded- Rating);
    Diff = round(sqrt((Rating-PredRatingBounded )*(Rating-PredRatingBounded )));
run;

proc sql;
create table rcm.AVG as
select *
from rcm.A_DataSetPredicted_adv
where Part = "T";




/******************************************************************/
/**********************Benchmark***********************************/
/******************************************************************/


Title3 "RMSE";
/**RMSE to var**/
proc sql;
select sqrt(avg(sqDiff))
into: RMSE_
from rcm.AVG
where Part = 'T';
quit;

/* Report Prediction Succes */
Title3 "Differences: Success, Diff1-Diff4, SUM";
proc iml;
use rcm.AVG ;
read all var {Diff} into diff;
close; 

t = countn (diff);

counts = J(6, 2, 0);

	do d = 1 to 5;
		c=0;
		do dr = 1 to nrow(diff);
			if diff[dr] = d-1 then do;
				c = c+1;
			end;
		end;
		
		p = 100 * c / t;
		counts[d,1] = c;
		counts[d,2] = p;	
	end;
counts[6,1] = sum (counts [,1]);
counts[6,2] = sum (counts [,2]);
print counts;
quit;


/* Report Prediction Succes FOR EXCEL*/
Title3 "Differences: Success, Diff1-Diff4, SUM, FOR EXCEL " ;
proc iml;
use rcm.AVG ;
read all var {Diff} into diff;
close; 

t = countn (diff);

counts = J(6, 2, 0);

	do d = 1 to 5;
		c=0;
		do dr = 1 to nrow(diff);
			if diff[dr] = d-1 then do;
				c = c+1;
			end;
		end;
		
		p = 100 * c / t;
		counts[d,1] = c ;
		counts[d,2] = p / 100;	
	end;
counts[6,1] = sum (counts [,1]);
counts[6,2] = sum (counts [,2]);

print counts;
quit;


