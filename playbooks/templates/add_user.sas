/* Specify connection options. Use an unrestricted user ID. */
options metaserver='sasgridmeta1.grid.sas';
options metaport=8561;
options metauser="sasadm@saspw";
options metapass='Adminadmin1!';

/* Specify the directory for the extracted  metadata (target tables).*/
libname meta "/home/sasinst";

/* Specify the directory  for the comparison output (change tables).*/
*libname updates
"drive:\path\METAupdates";

/* Extract identity information from AD (master).2*/
*%let _EXTRACTONLY = ;
*%include "drive:\path\myimportad.sas";

/* Extract identity information from the metadata (target).*/
*%mduextr(libref=meta);
/*proc print data=meta.group_info(where=(name='SASUSERS')); run;*/

/* Initialize the macro variables that create canonical tables. */
%mduimpc();

/* Create the person table. */
data &persontbla ;
     %definepersoncols;
     infile datalines delimiter=',' missover;
         input keyid name description title;
    datalines;
P001,sasevs,sasevs,
;

/* Create the phone table. */
data &phonetbla ;
     %definephonecols;
     infile datalines delimiter=',' missover;
         input keyid phoneNumber phoneType;
    datalines;
P001,,
;

/* Create the location table. */
data &locationtbla ;
     %definelocationcols;
     infile datalines delimiter=',' missover;
         input keyid locationName locationType address city postalcode area
country;
    datalines;
P001,,,,,,,
;

/* Create the email table. */
data &emailtbla ;
     %defineemailcols;
     infile datalines delimiter=',' missover;
         input keyid emailAddr emailtype;
    datalines;
P001,,
;

/* Create the idgrp table. */
data &idgrptbla ;
     %defineidgrpcols;
     infile datalines delimiter=',' missover;
         input keyid name description grpType;
    datalines;
G001,,,
;

/* Create the grpmems table. */
data &idgrpmemstbla;
     %defineidgrpmemscols;
     infile datalines delimiter=',' missover;
         input grpkeyid memkeyid;
    datalines;
G001,P001
;

/* Create the authdomain table. */
data &authdomtbla;
     %defineauthdomcols;
     infile datalines delimiter=',' missover;
         input keyid authDomName;
    datalines;
A001,DefaultAuth
;

/* Create the logins table. */
data &logintbla;
     %definelogincols;
     infile datalines delimiter=',' missover;
         input keyid userid password authdomkeyid;
    datalines;
P001,sasevs,Adminadmin1!,A001
;

/* Load the information from the work library into the metadata server. */
%mduimplb();
