/*Data directory specification*/   
LIBNAME rcm '/folders/myfolders/KNN/Data' ;

/*Used DataSet*/
%let InDS= rcm._base_1M;


/******************************************************************/
/**********************Recommendation******************************/
/******************************************************************/


/*Divide BaseTable into L (80%) & T(20%) Parts*/
data rcm.M_DataSet_LT;
set &InDS;
call streaminit(123); /* set random number seed */
   u = rand("Uniform"); /* u ~ U[0,1] */
   if U <=0.8 then 
   Part = "L" ;
   else
   Part = "T";
run;

/*TODO: avg/median*/
/* Rating median, store into a macro variable: DataSetMedian */
Title3 "DataSet Median";
PROC SQL ;
SELECT round(MEDIAN(Rating),1)
into: DataSetMedian 
FROM rcm.M_DataSet_LT 
WHERE Part='L';
QUIT;

/*Rating Median based on Item*/
proc sql;
create table rcm.M_Med_ItemID as 
select ItemID, MEDIAN(Rating) as MedRatingOnItem
from rcm.M_DataSet_LT
where Part = "L" 
group by ItemID;
quit;

/*Rating Median based on User*/
proc sql;
create table rcm.M_Med_UserID as 
select UserID, MEDIAN(Rating) as MedRatingOnUser
from rcm.M_DataSet_LT
where Part = "L" 
group by UserID;
quit;

/*
proc sql;
create table rcm.M_med_userID as 
select UserID, median (Rating) as MedRatingOnUser ,&DataSetMedian - Median(rating) as Bias 
from rcm.m_dataset_lt 
where Part='L'
group by UserID;
quit;
*/

/*Merge dataSet table with Item&User-Median rating*/
proc sql;
create table rcm.M_DataSet_Prediction as 
select
t1.ItemID ,
t1.UserID ,
Rating ,
Part ,
MedRatingOnItem, 
MedRatingOnUser, 
MedRatingOnItem + MedRatingOnUser - &DataSetMedian as PredRating
From (rcm.M_DataSet_LT t1 
left Join rcm.M_Med_ItemID t2 on t1.ItemID = t2.ItemID)
left join rcm.M_Med_UserID t3 on t1.UserID = t3.UserID;
quit;

/* replace missing values: globalAVG */
proc stdize 
	data=rcm.M_DataSet_Prediction
	reponly missing=&AvgRating 
	out=rcm.M_DataSet_Prediction;
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
data rcm.M_DataSet_Prediction_adv;
set rcm.M_DataSet_Prediction ;
    PredRatingBounded= 	min(max(PredRating, &MinRating ),&MaxRating);
	SqDiff = (PredRatingBounded- Rating)*(PredRatingBounded- Rating);
    Diff = round(sqrt((Rating-PredRatingBounded )*(Rating-PredRatingBounded )));
run;


/* Cut out learning part */
proc sql;
create table rcm.MEDIAN as
select *
from rcm.M_DataSet_Prediction_adv
where Part = "T";


/******************************************************************/
/**********************Benchmark***********************************/
/******************************************************************/


Title3 "RMSE";
/**RMSE to var**/
proc sql;
select sqrt(avg(sqDiff))
into: RMSE_
from rcm.MEDIAN 
where Part = 'T';
quit;

/* Report Prediction Succes */
Title3 "Differences: Success, Diff1-Diff4, SUM";
proc iml;
use rcm.MEDIAN ;
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
use rcm.MEDIAN ;
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