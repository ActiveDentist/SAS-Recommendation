/**************************************************************************************/
LIBNAME reco'/folders/myfolders/KNN/Data'; 		/* Data directory specification       */  
%let InDS= reco._base;							/* Basic DataSet                      */
%let RandomSeed = 955;							/* Dividing random number seed)       */
%let k=80; 	/* default 50 */					/* Count of nearest neighbors to find */ 
%let DistanceMethod=cosine;						/* Distance measure method	  		  */
/**************************************************************************************/
%let _sdtm=%sysfunc(datetime()); 	    		/* Store Script Start Time			  */
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
create table reco.AVG_UserID as 
select UserID, avg (Rating) as AvgUserRating, avg (Rating) - &AvgRating as Bias
from reco.Sample 
where DevSample = "L" group by UserID;
quit;








/*** Sparse to dense ***/
proc iml;
/* Read data*/
use reco.sample;
read all var{Rating UserId ItemId} where(DevSample="L");
close;
/* combine UserId ItemId Rating into a sparse matrix */
/*       Value	||	Row	  ||  Col     				 */
sparse = Rating || UserId || ItemId;

/* Conversion sparse to dense matrix*/
/*			ItemID   				*/
/*	UserID	Rating          		*/
dense = full(sparse);
/* Store data */
create reco.base_dense from dense;
append from dense;
close reco.base_dense;
quit;

/*** Rating: Set missing values instead 0 ***/
data reco.base_dense_null; 
set reco.base_dense;
array nums _numeric_;
 
do over nums;
 if nums=0 then nums=.;	
end;
run;

/* Store Recommendation Start Time */
%let _recostart=%sysfunc(datetime()); 			







/* Rating normalization:  Substract userAVG from rating ************************************************    NORMALIZATION      */
/* base_dense_normalized OUT */
/* base_dense_null       IN  */
proc iml;
use reco.base_dense; /*_null*/
read all into ratings;
close;

use reco.AVG_UserID;
read all into avgs;
close;

do user = 1 to nrow(ratings);
	do item = 1 to ncol(ratings);
		if ratings [user,item] ^=0 then do; /*.*/
			ratings [user,item] = ratings [user,item] - avgs [user , 2];
		end;
	end;
end;

create reco.base_dense_normalized from ratings ;
append from ratings ;
close reco.base_dense_normalized ;
quit;





/* Ridit – transform rating to 0-1 interval ************************************************************         RIDIT    */
/* base_dense_ridit       OUT */
/* base_dense_null        IN  */
PROC FREQ DATA=reco.sample(where=(DevSample="L"))
	ORDER=INTERNAL
	noprint;
	TABLES Rating / 
		OUT=work.OneWay 
		SCORES=ridit;
	by UserId;
RUN;

data reco.ridit;
set work.OneWay;
retain cumsum;
if UserId ^= lag(UserId) then cumsum = 0;
cumsum = cumsum + percent;
ridit = (cumsum - percent/2)/100;
run;

proc sql;
create table reco.ridit_sparse as
	select a.UserID
		,  a.ItemID
		,  a.rating
		,  b.ridit
	from reco.sample a
	left join reco.ridit b
	on a.UserID = b.UserID and a.rating = b.rating
	where DevSample="L";	
quit;

proc iml;
use reco.ridit_sparse;
read all var{ridit UserId ItemId};
close;

sparse = ridit|| UserId || ItemId;
dense = full(sparse);

create reco.ridit_dense from dense;
append from dense;
close reco.ridit_dense;
quit;



/* Users distances ************************************************************************************        DISTANCE    */
proc distance 
	SHAPE=SQR
	REPONLY
	data=reco.ridit_dense /* ridit*/ /* avged */ /* normalized  */
	method= &DistanceMethod 
	out=reco.distance;
    var ratio /*interval*/ (Col:);
   run;
   
/* Remove diagonal distances */
proc iml;
use reco.distance;
read all into inputData;
close;

do d = 1 to ncol(inputData);
	inputData[d,d] =. ;
end;

create reco.distance_diag from inputData;
append from inputData;
close reco.distance_diag ;
quit;


/*** k-NN ***************************************************************************************************        k-NN       */
proc iml;
/* Read data */
use reco.base_dense_normalized  ;
read all var _num_ into rating;
close;


use reco.distance_diag;
read all var _all_ into distances;
close;

use reco.AVG_UserID;
read all var{AvgUserRating} into userAVG;
close;

/* Settings */
k = &k; 

/* Initialisation */
nearestNeighbor = J(nrow(rating ), k, 0); 			/* Matrix of nearest neighbors */
recommendation = J(nrow(rating), ncol(rating), 0);	/* Matrix with the estimated rating */
distance = J(nrow(rating ), 1, 0 ) /*10**10*/; 	    /* Vector of distances *************************************************************/

/* Loop - get the nearest neighbours */
do reference = 1 to nrow(rating );
	
	distance = distances[ ,reference];
	
	
	
	/* Sort distances in descending(1–N) order, return indices */
	call sortndx(ndx, distance, {1}, {1} /*,descend*/); 
	
	/* Sort & return distances in descending order */
	call sort(distance,{1},{1});
	
	topDistance = distance [1:k];
	
	/* Store k nearest neighbours */
	nearestNeighbor[reference,] = ndx[1:k]`; 
	
	/* Save distances sum */
	scalesum = topDistance [:,1]; 
	
	/* Prepare scales: distance/SUM(distances) */
	scales = topDistance [ ,1] / scalesum;
	
	/* ratings * scales */
	scalRat = scales` * rating[nearestNeighbor[reference,],];
	
	/* Create Binary Rating Matrix */
	binM = (rating[nearestNeighbor[reference,],]^=0);
	
	/* Create Matrix to fix scales (zero ratings) */ 
	fix = scales` * binM;
	
	
	/* Get recommendation */
	recommendation[reference,] = userAVG[reference] + (scalRat / fix );
	

	/* Get recommendation (average recommendation of the nearest neighbours) 
	recommendation[reference,] = mean(rating[nearestNeighbor[reference,],]);
	*/

	
end;	

/* Convert dense to sparse matrix */
result = sparse(recommendation); 

/* Store data */
create reco.knn_all from result;
append from result;
close reco.knn_all;

quit;


/*** Set global AVG to not seen films ***/
data reco.knn_all; 
set reco.knn_all;
array nums _numeric_;
 
do over nums;
 if nums=. then nums=&AvgRating  ;	
end;
run;



/* Rename columns */
proc datasets library=reco nolist;
modify knn_all;
rename Col1 = PredRating;
rename Col2 = UserId;
rename Col3 = ItemId;
quit;


 
/* Debias k-NN rating prediction and bound to limits */
data   reco.knn_all_debiased   /* (keep=UserID ItemID PredRating PredRatingBounded) */ /view=reco.knn_all_debiased;
	 merge reco.knn_all         (keep=UserID ItemID PredRating in=a)
		   reco.AVG_UserID (keep=UserId Bias in=b);
	 by UserId;
	 if a & b;
	/* PredRating = PredRating + Bias;*/
	 PredRatingBounded = min(max(PredRating, &MinRating ),&MaxRating);
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
%let PredRating = PredRatingBounded;		/* PredRatingBounded */
%let tableName  = reco.knn_all_debiased; /* reco.knn_all_debiased_II */

 
/* Merge target and prediction & calculate Square Error */
data reco.rmse_merged(keep=SquareDiff Rating &PredRating);
     merge reco.sample(keep=UserId ItemID Rating DevSample where=(DevSample="T") in=a)
           &tableName(keep=UserId ItemID &PredRating in=b);
     by UserId ItemID;
     if a & b;
     SquareDiff = (Rating-&PredRating)*(Rating-&PredRating);
     Diff 		= round(sqrt((Rating-&PredRating )*(Rating-&PredRating )));
run;

/* Save rounded Predictions */
proc sql;
create table reco.rmse_success as
	select round(sqrt(SquareDiff)) as Diff
	from reco.rmse_merged;
quit;


Title3 "RMSE";
/* Print RMSE */
proc sql;
select sqrt(avg(SquareDiff))
into: RMSE
from reco.rmse_merged;
quit;

/* Report Prediction Succes */
Title3 "Differences: Success, Diff1-Diff4, SUM";
proc iml;
use reco.rmse_success ;
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


/* Report Prediction Succes FOR EXCEL*/
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