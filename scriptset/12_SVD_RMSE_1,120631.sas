/**************************************************************************************/
LIBNAME reco'/folders/myfolders/KNN/Data'; 		/* Data directory specification       */  
%let InDS= reco._base;							/* Basic DataSet                      */
%let RandomSeed = 955;							/* Dividing random number seed)       */
%let k=80; 	/* default 50 */					/* Count of nearest neighbors to find */ 
%let DistanceMethod=cosine;						/* Distance measure method	  		  */
%let N=20; 	/* default 20 */					/* number of principal components to be computed*/
/**************************************************************************************/
%let _sdtm=%sysfunc(datetime()); 					/* Store Script Start Time		  */
/**************************************************************************************/




/*** Sampling - divide to training (L) and testing(T) ***/
data reco.Sample;
    set &InDS;
    if _n_=1 then
        call streaminit(&randomseed);
    U=rand('uniform');
    if U<=0.80 
	then DevSample='L';
    else DevSample='T';
run;

/* Sort */
proc sort data=reco.Sample;
by UserId ItemId;
run;







/*Max & Min Ratings*/
Title3 "Max Rating";
Proc sql noprint;
select max(rating)
into: MaxRating
from &InDS;
quit;

Title3 "Min Rating";
Proc sql noprint;
select min(rating)
into: MinRating
from &InDS;
quit;



/*AVG Rating to variable: AvgRating */
Title3 "AVG DataSet Rating";
proc sql;
SELECT AVG(Rating) 
Into: AvgRating 
FROM reco.Sample
where DevSample= "L";
quit;

/*AVG Item Rating */
proc sql;
create table reco.AVG_ItemID as 
select ItemID, avg (Rating) as AvgRatingOnItem
from reco.Sample
where DevSample = "L" group by ItemID;
quit;

/*AVG User Rating */
proc sql;
create table reco.average_user as 
select UserID, avg (Rating) as AvgUserRating, avg (Rating) - &AvgRating as Bias
from reco.Sample 
where DevSample = "L" group by UserID;
quit;








/*** Normalise by User bias ***/
proc sql;
	create table reco.base_norm as
	select a.UserId
		 , a.ItemId
		 , a.rating+b.bias as Rating
		 , a.DevSample
	from reco.sample a
	join reco.average_user b
	on a.UserId = b.UserId;
quit;

/*** Sparse to dense ***/
proc iml;
/* Read data*/
use reco.base_norm;
read all var{Rating UserId ItemId} where(DevSample="L");
close;

/* combine UserId ItemId Rating into a matrix sparse */
sparse = Rating || UserId || ItemId;

/* Conversion */
dense = full(sparse);

/* Store data */
create reco.base_dense from dense;
append from dense;
close reco.base_dense;

quit;

/*** Replace zeros with missings ***/
data reco.base_imputed; 
set reco.base_dense;
array nums _numeric_;
 
do over nums;
 if nums=0 then nums=.;	
end;
run;


/* Store Recommendation Start Time */
%let _recostart=%sysfunc(datetime()); 			



/* Item AVG to Missing rating */ /******************************************************************* null >>> ItemAVG */
proc iml;
use reco.base_imputed;
read all into rating;
close;
do item = 1 to ncol(rating);
itemAVG = /*mean(rating[ ,item])*/ sum(rating[ ,item])/countn(rating[ ,item]);
do replacement = 1 to nrow(rating);
if rating [replacement ,item] =. then do;
rating [replacement ,item] = itemAVG ;
end;
end;
end;
create reco.base_dense_avged from rating ;
append from rating ;
close reco.base_dense_avged;
quit;

/* Replace missing when no one has ever watched the movie */
data reco.base_dense_avged;
set reco.base_dense_avged;
array nums _numeric_;
do over nums;
if nums=. then nums=&AvgRating;
end;
run;



/*** SVD. See: http://www.cs.carleton.edu/cs_comps/0607/recommend/recommender/svd.html for more details ***/
proc princomp data=reco.BASE_DENSE_AVGED
	out=reco.base_svd
	outstat=reco.base_svd_score
	noprint
	cov 
	noint
	n=20;
    var Col1-Col1500;   
run;

proc iml;
	/* Read data */
	use reco.base_svd;
	   read all var _NUM_ into princ[colname=NumerNames];
	close;

	use reco.base_svd_score;
	   read all var _NUM_ into score[colname=NumerNames];
	close;
	 
	/* Select only useful data from the input */
	length = ncol(princ);
	princ = princ[ , length-20+1:length];
	length = nrow(score);
	score = score[length-20+1:length, ];
	
	/* Matrix multiplication */
	xhat = princ * score;

	/* Dense to sparse */
	output = sparse(xhat);
	 
	/* Store data */
	create reco.svd from output;
	append from output;
	close reco.svd;
quit;


/*** Rename columns ***/
proc datasets library=reco nolist;
modify svd;
rename Col1 = PredRating;
rename Col2 = UserId;
rename Col3 = ItemId;
quit;

/*** Normalise by UserItem bias ***/
proc sql;
	create table reco.svd as
	select a.UserId
		 , a.ItemId
		 , a.PredRating-b.bias as PredRating
	from reco.svd a
	join reco.average_user b
	on a.UserId = b.UserId;
quit;

/* Replace missings & bind to limits */
data reco.svd; 
set reco.svd;
ImputedRating = PredRating;
if ImputedRating = . then ImputedRating = 3.53;
PredRating = min(max(ImputedRating, 1), 5);
run;

/* Measure recommendation elapsed time */
%let _recoend=%sysfunc(datetime());
%let _recoruntm=%sysfunc(putn(&_recoend - &_recostart, 12.4));
%put It took &_recoruntm second to do recommendations;
Title3 "Elapsed time";
proc iml;
print "It took " &_recoruntm"second to do recommendations";
quit;



/******************************************************/
/********************* EVALUATION *********************/
/******************************************************/






 
/* Data to evaluate*/
%let PredRating = PredRating;		/* PredRatingBounded */
%let tableName  = reco.svd; /* reco.knn_all_debiased_II */

/* Tell SAS that the table is sorted to accelerate subsequent queries 
proc sort data=&tableName presorted;
by UserId ItemId;
run;
 
 */
 
/* Merge target and prediction & calculate Square Error */
data reco.rmse_merged(keep=SquareDiff Rating &PredRating Diff);
     merge reco.sample(keep=UserId ItemID Rating DevSample where=(DevSample="T") in=a)
           &tableName(keep=UserId ItemID &PredRating in=b);
     by UserId ItemID;
     if a & b;
     SquareDiff = (Rating-&PredRating)*(Rating-&PredRating);
     Diff 		= round(sqrt((Rating-&PredRating )*(Rating-&PredRating )));
run;


Title3 "RMSE";
/* Print RMSE */
proc sql;
select sqrt(avg(SquareDiff))
into: RMSE
from reco.rmse_merged;
quit;


/* Report Prediction Success */
Title3 "Differences: Success, Diff1-Diff4, SUM";
proc iml;
use reco.rmse_merged;
read all var {Diff} into diff;
close; 

t = countn (diff);

counts = J(2, 6, 0);

	do d = 1 to 5;
		c=0;
		do dr = 1 to nrow(diff);
			if diff[dr] = d-1 then do;
				c = c+1;
			end;
		end;
		
		p = 100 * c / t;
		counts[1,d] = c;
		counts[2,d] = p;	
	end;
counts[1,6] = sum (counts [1, ]);
counts[2,6] = sum (counts [2, ]);
print counts;

create reco.counts from counts;
append from counts;
close reco.counts;

quit;


/* Report Prediction Success FOR EXCEL*/
Title3 "Differences: Success, Diff1-Diff4, SUM, FOR EXCEL " ;
proc iml;
use reco.counts ;
read all var _all_ into counts;
close; 

fruifulness = counts`;
fruifulness [ ,2]  = fruifulness [ ,2] / 100;
print fruifulness;
quit;


/* Measure elapsed time */
%let _edtm=%sysfunc(datetime());
%let _runtm=%sysfunc(putn(&_edtm - &_sdtm, 12.4));
%put It took &_runtm second to run the script;
Title3 "Elapsed time";
proc iml;
print "It took " &_runtm "second to run the script";
quit;

