-- BIZBOT-STOREFRONT-CONTENT-CONTRACT-001. Presentation only; no ordering,
-- notification, payment, device or printing authority is changed.
-- Local filename allocated by the reviewed filesystem-only UTC/CreateNew
-- alternative after CLI help execution was rejected before process creation.
begin;

-- GENERATED from pinned Unicode15.1/UAX29r43; see vendor/LICENSE.txt and provenance.json.
CREATE OR REPLACE FUNCTION app.storefront_content_property_v1(p_cp integer,p_property text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $unicode$
DECLARE v_ranges integer[]; lo integer:=0; hi integer; mid integer;
BEGIN
 IF p_cp IS NULL OR p_cp<0 OR p_cp>1114111 THEN RETURN false; END IF;
 CASE p_property
 WHEN 'Prepend' THEN v_ranges := ARRAY[1536,1541,1757,1757,1807,1807,2192,2193,2274,2274,3406,3406,69821,69821,69837,69837,70082,70083,71999,71999,72001,72001,72250,72250,72324,72329,73030,73030,73474,73474]::integer[];
WHEN 'CR' THEN v_ranges := ARRAY[13,13]::integer[];
WHEN 'LF' THEN v_ranges := ARRAY[10,10]::integer[];
WHEN 'Control' THEN v_ranges := ARRAY[0,9,11,12,14,31,127,159,173,173,1564,1564,6158,6158,8203,8203,8206,8207,8232,8238,8288,8303,65279,65279,65520,65531,78896,78911,113824,113827,119155,119162,917504,917535,917632,917759,918000,921599]::integer[];
WHEN 'Extend' THEN v_ranges := ARRAY[768,879,1155,1161,1425,1469,1471,1471,1473,1474,1476,1477,1479,1479,1552,1562,1611,1631,1648,1648,1750,1756,1759,1764,1767,1768,1770,1773,1809,1809,1840,1866,1958,1968,2027,2035,2045,2045,2070,2073,2075,2083,2085,2087,2089,2093,2137,2139,2200,2207,2250,2273,2275,2306,2362,2362,2364,2364,2369,2376,2381,2381,2385,2391,2402,2403,2433,2433,2492,2492,2494,2494,2497,2500,2509,2509,2519,2519,2530,2531,2558,2558,2561,2562,2620,2620,2625,2626,2631,2632,2635,2637,2641,2641,2672,2673,2677,2677,2689,2690,2748,2748,2753,2757,2759,2760,2765,2765,2786,2787,2810,2815,2817,2817,2876,2876,2878,2879,2881,2884,2893,2893,2901,2903,2914,2915,2946,2946,3006,3006,3008,3008,3021,3021,3031,3031,3072,3072,3076,3076,3132,3132,3134,3136,3142,3144,3146,3149,3157,3158,3170,3171,3201,3201,3260,3260,3263,3263,3266,3266,3270,3270,3276,3277,3285,3286,3298,3299,3328,3329,3387,3388,3390,3390,3393,3396,3405,3405,3415,3415,3426,3427,3457,3457,3530,3530,3535,3535,3538,3540,3542,3542,3551,3551,3633,3633,3636,3642,3655,3662,3761,3761,3764,3772,3784,3790,3864,3865,3893,3893,3895,3895,3897,3897,3953,3966,3968,3972,3974,3975,3981,3991,3993,4028,4038,4038,4141,4144,4146,4151,4153,4154,4157,4158,4184,4185,4190,4192,4209,4212,4226,4226,4229,4230,4237,4237,4253,4253,4957,4959,5906,5908,5938,5939,5970,5971,6002,6003,6068,6069,6071,6077,6086,6086,6089,6099,6109,6109,6155,6157,6159,6159,6277,6278,6313,6313,6432,6434,6439,6440,6450,6450,6457,6459,6679,6680,6683,6683,6742,6742,6744,6750,6752,6752,6754,6754,6757,6764,6771,6780,6783,6783,6832,6862,6912,6915,6964,6970,6972,6972,6978,6978,7019,7027,7040,7041,7074,7077,7080,7081,7083,7085,7142,7142,7144,7145,7149,7149,7151,7153,7212,7219,7222,7223,7376,7378,7380,7392,7394,7400,7405,7405,7412,7412,7416,7417,7616,7679,8204,8204,8400,8432,11503,11505,11647,11647,11744,11775,12330,12335,12441,12442,42607,42610,42612,42621,42654,42655,42736,42737,43010,43010,43014,43014,43019,43019,43045,43046,43052,43052,43204,43205,43232,43249,43263,43263,43302,43309,43335,43345,43392,43394,43443,43443,43446,43449,43452,43453,43493,43493,43561,43566,43569,43570,43573,43574,43587,43587,43596,43596,43644,43644,43696,43696,43698,43700,43703,43704,43710,43711,43713,43713,43756,43757,43766,43766,44005,44005,44008,44008,44013,44013,64286,64286,65024,65039,65056,65071,65438,65439,66045,66045,66272,66272,66422,66426,68097,68099,68101,68102,68108,68111,68152,68154,68159,68159,68325,68326,68900,68903,69291,69292,69373,69375,69446,69456,69506,69509,69633,69633,69688,69702,69744,69744,69747,69748,69759,69761,69811,69814,69817,69818,69826,69826,69888,69890,69927,69931,69933,69940,70003,70003,70016,70017,70070,70078,70089,70092,70095,70095,70191,70193,70196,70196,70198,70199,70206,70206,70209,70209,70367,70367,70371,70378,70400,70401,70459,70460,70462,70462,70464,70464,70487,70487,70502,70508,70512,70516,70712,70719,70722,70724,70726,70726,70750,70750,70832,70832,70835,70840,70842,70842,70845,70845,70847,70848,70850,70851,71087,71087,71090,71093,71100,71101,71103,71104,71132,71133,71219,71226,71229,71229,71231,71232,71339,71339,71341,71341,71344,71349,71351,71351,71453,71455,71458,71461,71463,71467,71727,71735,71737,71738,71984,71984,71995,71996,71998,71998,72003,72003,72148,72151,72154,72155,72160,72160,72193,72202,72243,72248,72251,72254,72263,72263,72273,72278,72281,72283,72330,72342,72344,72345,72752,72758,72760,72765,72767,72767,72850,72871,72874,72880,72882,72883,72885,72886,73009,73014,73018,73018,73020,73021,73023,73029,73031,73031,73104,73105,73109,73109,73111,73111,73459,73460,73472,73473,73526,73530,73536,73536,73538,73538,78912,78912,78919,78933,92912,92916,92976,92982,94031,94031,94095,94098,94180,94180,113821,113822,118528,118573,118576,118598,119141,119141,119143,119145,119150,119154,119163,119170,119173,119179,119210,119213,119362,119364,121344,121398,121403,121452,121461,121461,121476,121476,121499,121503,121505,121519,122880,122886,122888,122904,122907,122913,122915,122916,122918,122922,123023,123023,123184,123190,123566,123566,123628,123631,124140,124143,125136,125142,125252,125258,127995,127999,917536,917631,917760,917999]::integer[];
WHEN 'Regional_Indicator' THEN v_ranges := ARRAY[127462,127487]::integer[];
WHEN 'SpacingMark' THEN v_ranges := ARRAY[2307,2307,2363,2363,2366,2368,2377,2380,2382,2383,2434,2435,2495,2496,2503,2504,2507,2508,2563,2563,2622,2624,2691,2691,2750,2752,2761,2761,2763,2764,2818,2819,2880,2880,2887,2888,2891,2892,3007,3007,3009,3010,3014,3016,3018,3020,3073,3075,3137,3140,3202,3203,3262,3262,3264,3265,3267,3268,3271,3272,3274,3275,3315,3315,3330,3331,3391,3392,3398,3400,3402,3404,3458,3459,3536,3537,3544,3550,3570,3571,3635,3635,3763,3763,3902,3903,3967,3967,4145,4145,4155,4156,4182,4183,4228,4228,5909,5909,5940,5940,6070,6070,6078,6085,6087,6088,6435,6438,6441,6443,6448,6449,6451,6456,6681,6682,6741,6741,6743,6743,6765,6770,6916,6916,6971,6971,6973,6977,6979,6980,7042,7042,7073,7073,7078,7079,7082,7082,7143,7143,7146,7148,7150,7150,7154,7155,7204,7211,7220,7221,7393,7393,7415,7415,43043,43044,43047,43047,43136,43137,43188,43203,43346,43347,43395,43395,43444,43445,43450,43451,43454,43456,43567,43568,43571,43572,43597,43597,43755,43755,43758,43759,43765,43765,44003,44004,44006,44007,44009,44010,44012,44012,69632,69632,69634,69634,69762,69762,69808,69810,69815,69816,69932,69932,69957,69958,70018,70018,70067,70069,70079,70080,70094,70094,70188,70190,70194,70195,70197,70197,70368,70370,70402,70403,70463,70463,70465,70468,70471,70472,70475,70477,70498,70499,70709,70711,70720,70721,70725,70725,70833,70834,70841,70841,70843,70844,70846,70846,70849,70849,71088,71089,71096,71099,71102,71102,71216,71218,71227,71228,71230,71230,71340,71340,71342,71343,71350,71350,71462,71462,71724,71726,71736,71736,71985,71989,71991,71992,71997,71997,72000,72000,72002,72002,72145,72147,72156,72159,72164,72164,72249,72249,72279,72280,72343,72343,72751,72751,72766,72766,72873,72873,72881,72881,72884,72884,73098,73102,73107,73108,73110,73110,73461,73462,73475,73475,73524,73525,73534,73535,73537,73537,94033,94087,94192,94193,119142,119142,119149,119149]::integer[];
WHEN 'L' THEN v_ranges := ARRAY[4352,4447,43360,43388]::integer[];
WHEN 'V' THEN v_ranges := ARRAY[4448,4519,55216,55238]::integer[];
WHEN 'T' THEN v_ranges := ARRAY[4520,4607,55243,55291]::integer[];
WHEN 'ZWJ' THEN v_ranges := ARRAY[8205,8205]::integer[];
WHEN 'Extended_Pictographic' THEN v_ranges := ARRAY[169,169,174,174,8252,8252,8265,8265,8482,8482,8505,8505,8596,8601,8617,8618,8986,8987,9000,9000,9096,9096,9167,9167,9193,9203,9208,9210,9410,9410,9642,9643,9654,9654,9664,9664,9723,9726,9728,9733,9735,9746,9748,9861,9872,9989,9992,10002,10004,10004,10006,10006,10013,10013,10017,10017,10024,10024,10035,10036,10052,10052,10055,10055,10060,10060,10062,10062,10067,10069,10071,10071,10083,10087,10133,10135,10145,10145,10160,10160,10175,10175,10548,10549,11013,11015,11035,11036,11088,11088,11093,11093,12336,12336,12349,12349,12951,12951,12953,12953,126976,127231,127245,127247,127279,127279,127340,127345,127358,127359,127374,127374,127377,127386,127405,127461,127489,127503,127514,127514,127535,127535,127538,127546,127548,127551,127561,127994,128000,128317,128326,128591,128640,128767,128884,128895,128981,129023,129036,129039,129096,129103,129114,129119,129160,129167,129198,129279,129292,129338,129340,129349,129351,129791,130048,131069]::integer[];
WHEN 'InCB_Linker' THEN v_ranges := ARRAY[2381,2381,2509,2509,2765,2765,2893,2893,3149,3149,3405,3405]::integer[];
WHEN 'InCB_Consonant' THEN v_ranges := ARRAY[2325,2361,2392,2399,2424,2431,2453,2472,2474,2480,2482,2482,2486,2489,2524,2525,2527,2527,2544,2545,2709,2728,2730,2736,2738,2739,2741,2745,2809,2809,2837,2856,2858,2864,2866,2867,2869,2873,2908,2909,2911,2911,2929,2929,3093,3112,3114,3129,3160,3162,3349,3386]::integer[];
WHEN 'InCB_Extend' THEN v_ranges := ARRAY[768,846,848,879,1155,1159,1425,1469,1471,1471,1473,1474,1476,1477,1479,1479,1552,1562,1611,1631,1648,1648,1750,1756,1759,1764,1767,1768,1770,1773,1809,1809,1840,1866,2027,2035,2045,2045,2070,2073,2075,2083,2085,2087,2089,2093,2137,2139,2200,2207,2250,2273,2275,2303,2364,2364,2385,2388,2492,2492,2558,2558,2620,2620,2748,2748,2876,2876,3132,3132,3157,3158,3260,3260,3387,3388,3640,3642,3656,3659,3768,3770,3784,3787,3864,3865,3893,3893,3895,3895,3897,3897,3953,3954,3956,3956,3962,3965,3968,3968,3970,3972,3974,3975,4038,4038,4151,4151,4153,4154,4237,4237,4957,4959,5908,5908,6098,6098,6109,6109,6313,6313,6457,6459,6679,6680,6752,6752,6773,6780,6783,6783,6832,6845,6847,6862,6964,6964,7019,7027,7083,7083,7142,7142,7223,7223,7376,7378,7380,7392,7394,7400,7405,7405,7412,7412,7416,7417,7616,7679,8205,8205,8400,8412,8417,8417,8421,8432,11503,11505,11647,11647,11744,11775,12330,12335,12441,12442,42607,42607,42612,42621,42654,42655,42736,42737,43052,43052,43232,43249,43307,43309,43443,43443,43696,43696,43698,43700,43703,43704,43710,43711,43713,43713,43766,43766,44013,44013,64286,64286,65056,65071,66045,66045,66272,66272,66422,66426,68109,68109,68111,68111,68152,68154,68159,68159,68325,68326,68900,68903,69291,69292,69373,69375,69446,69456,69506,69509,69744,69744,69759,69759,69818,69818,69888,69890,69939,69940,70003,70003,70090,70090,70198,70198,70377,70378,70459,70460,70502,70508,70512,70516,70726,70726,70750,70750,70851,70851,71104,71104,71351,71351,71467,71467,71738,71738,71998,71998,72003,72003,72244,72244,72263,72263,72345,72345,73026,73026,73028,73029,73111,73111,73538,73538,92912,92916,92976,92982,113822,113822,119141,119141,119143,119145,119150,119154,119163,119170,119173,119179,119210,119213,119362,119364,122880,122886,122888,122904,122907,122913,122915,122916,122918,122922,123023,123023,123184,123190,123566,123566,123628,123631,124140,124143,125136,125142,125252,125258]::integer[];
 ELSE RETURN false;
 END CASE;
 hi:=array_length(v_ranges,1)/2-1;
 WHILE lo<=hi LOOP
  mid:=(lo+hi)/2;
  IF p_cp<v_ranges[mid*2+1] THEN hi:=mid-1;
  ELSIF p_cp>v_ranges[mid*2+2] THEN lo:=mid+1;
  ELSE RETURN true; END IF;
 END LOOP;
 RETURN false;
END $unicode$;
CREATE OR REPLACE FUNCTION app.storefront_content_gcb_v1(p_cp integer)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $unicode$
DECLARE k text;
BEGIN
 IF p_cp BETWEEN 44032 AND 55203 THEN RETURN CASE WHEN (p_cp-44032)%28=0 THEN 'LV' ELSE 'LVT' END; END IF;
 FOREACH k IN ARRAY ARRAY['CR','LF','Control','L','V','T','Extend','ZWJ','Regional_Indicator','Prepend','SpacingMark'] LOOP
  IF app.storefront_content_property_v1(p_cp,k) THEN RETURN k; END IF;
 END LOOP;
 RETURN 'Other';
END $unicode$;
CREATE OR REPLACE FUNCTION app.storefront_content_grapheme_boundaries_v1(p_text text)
RETURNS integer[] LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $unicode$
DECLARE c integer[]:='{}'; g text[]:='{}'; result integer[]:=ARRAY[0]; n integer; i integer; j integer; a text; b text; join_cluster boolean; link boolean; cnt integer;
BEGIN
 IF p_text IS NULL THEN RETURN NULL; END IF;
 n:=char_length(p_text);IF n=0 THEN RETURN result;END IF;
 FOR i IN 1..n LOOP c:=array_append(c,ascii(substr(p_text,i,1)));g:=array_append(g,app.storefront_content_gcb_v1(c[i]));END LOOP;
 FOR i IN 2..n LOOP
  a:=g[i-1];b:=g[i];join_cluster:=false;
  IF a='CR' AND b='LF' THEN join_cluster:=true;
  ELSIF a=ANY(ARRAY['Control','CR','LF']) OR b=ANY(ARRAY['Control','CR','LF']) THEN join_cluster:=false;
  ELSIF a='L' AND b=ANY(ARRAY['L','V','LV','LVT']) THEN join_cluster:=true;
  ELSIF a=ANY(ARRAY['LV','V']) AND b=ANY(ARRAY['V','T']) THEN join_cluster:=true;
  ELSIF a=ANY(ARRAY['LVT','T']) AND b='T' THEN join_cluster:=true;
  ELSIF b=ANY(ARRAY['Extend','ZWJ','SpacingMark']) OR a='Prepend' THEN join_cluster:=true;
  ELSE
   IF app.storefront_content_property_v1(c[i],'InCB_Consonant') THEN
    j:=i-1;link:=false;
    WHILE j>=1 AND (app.storefront_content_property_v1(c[j],'InCB_Extend') OR app.storefront_content_property_v1(c[j],'InCB_Linker')) LOOP link:=link OR app.storefront_content_property_v1(c[j],'InCB_Linker');j:=j-1;END LOOP;
    join_cluster:=link AND j>=1 AND app.storefront_content_property_v1(c[j],'InCB_Consonant');
   END IF;
   IF NOT join_cluster AND a='ZWJ' AND app.storefront_content_property_v1(c[i],'Extended_Pictographic') THEN
    j:=i-2;WHILE j>=1 AND g[j]='Extend' LOOP j:=j-1;END LOOP;
    join_cluster:=j>=1 AND app.storefront_content_property_v1(c[j],'Extended_Pictographic');
   END IF;
   IF NOT join_cluster AND a='Regional_Indicator' AND b=a THEN
    j:=i-1;cnt:=0;WHILE j>=1 AND g[j]='Regional_Indicator' LOOP cnt:=cnt+1;j:=j-1;END LOOP;join_cluster:=cnt%2=1;
   END IF;
  END IF;
  IF NOT join_cluster THEN result:=array_append(result,i-1);END IF;
 END LOOP;
 RETURN array_append(result,n);
END $unicode$;
CREATE OR REPLACE FUNCTION app.storefront_content_space_v1(p_cp integer)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $unicode$
 SELECT coalesce(p_cp IN(32,133,160,5760,8232,8233,8239,8287,12288,65279) OR p_cp BETWEEN 8192 AND 8202,false)
$unicode$;
CREATE OR REPLACE FUNCTION app.storefront_content_text_v1(p_text text,p_max integer,p_legacy boolean)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $unicode$
DECLARE n integer; cp integer; i integer;
BEGIN
 IF p_max IS NULL OR p_max<1 OR p_legacy IS NULL THEN RETURN false;END IF;
 IF p_text IS NULL THEN RETURN true;END IF;
 n:=char_length(p_text);IF n<1 OR n>p_max THEN RETURN false;END IF;
 FOR i IN 1..n LOOP cp:=ascii(substr(p_text,i,1));
  IF cp<=31 OR cp=127 OR (NOT p_legacy AND (cp BETWEEN 128 AND 159 OR cp IN(8232,8233))) THEN RETURN false;END IF;
 END LOOP;
 RETURN NOT app.storefront_content_space_v1(ascii(substr(p_text,1,1))) AND NOT app.storefront_content_space_v1(ascii(substr(p_text,n,1)));
END $unicode$;
CREATE OR REPLACE FUNCTION app.storefront_content_hero_format_valid_v1(p_text text,p_start integer,p_end integer,p_break integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $unicode$
DECLARE n integer; bounds integer[];
BEGIN
 IF p_start IS NULL AND p_end IS NULL AND p_break IS NULL THEN RETURN true;END IF;
 IF p_text IS NULL OR NOT app.storefront_content_text_v1(p_text,120,true) THEN RETURN false;END IF;
 IF position(chr(133) IN p_text)>0 OR position(chr(8232) IN p_text)>0 OR position(chr(8233) IN p_text)>0 THEN RETURN false;END IF;
 n:=char_length(p_text);bounds:=app.storefront_content_grapheme_boundaries_v1(p_text);
 IF (p_start IS NULL)<>(p_end IS NULL) THEN RETURN false;END IF;
 IF p_start IS NOT NULL THEN
  IF p_start<0 OR p_end<=p_start OR p_end>n OR p_end-p_start>60 THEN RETURN false;END IF;
  IF app.storefront_content_space_v1(ascii(substr(p_text,p_start+1,1))) OR app.storefront_content_space_v1(ascii(substr(p_text,p_end,1))) OR (p_start>0 AND NOT app.storefront_content_space_v1(ascii(substr(p_text,p_start,1)))) OR (p_end<n AND NOT app.storefront_content_space_v1(ascii(substr(p_text,p_end+1,1)))) OR NOT(p_start=ANY(bounds)) OR NOT(p_end=ANY(bounds)) THEN RETURN false;END IF;
 END IF;
 IF p_break IS NOT NULL THEN
  IF p_break<1 OR p_break>=n THEN RETURN false;END IF;
  IF app.storefront_content_space_v1(ascii(substr(p_text,p_break+1,1))) OR NOT app.storefront_content_space_v1(ascii(substr(p_text,p_break,1))) OR NOT(p_break=ANY(bounds)) OR (p_start IS NOT NULL AND p_start<p_break AND p_break<p_end) THEN RETURN false;END IF;
 END IF;
 RETURN true;
END $unicode$;
REVOKE ALL ON FUNCTION app.storefront_content_property_v1(integer,text),app.storefront_content_gcb_v1(integer),app.storefront_content_grapheme_boundaries_v1(text),app.storefront_content_space_v1(integer),app.storefront_content_text_v1(text,integer,boolean),app.storefront_content_hero_format_valid_v1(text,integer,integer,integer) FROM PUBLIC,anon,authenticated,service_role;


create function app.storefront_content_keys_v1(p_value jsonb,p_keys text[])
returns boolean language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(p_value)='object'
   and (select count(*) from jsonb_object_keys(case when jsonb_typeof(p_value)='object' then p_value else '{}'::jsonb end))=cardinality(p_keys)
   and p_value ?& p_keys,false);
$$;
create function app.storefront_content_uuid_v1(p_value jsonb)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(p_value)='string' and (p_value#>>'{}') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false);
$$;
create function app.storefront_content_input_text_v1(p_value jsonb,p_max integer,p_legacy boolean)
returns boolean language plpgsql immutable set search_path='' as $$
declare t text; cp integer; i integer;
begin
 if p_value='null'::jsonb then return true; end if;
 if jsonb_typeof(p_value) is distinct from 'string' then return false; end if;
 t:=p_value#>>'{}';
 -- Validate RAW controls before trimming. An invalid edge character must not
 -- disappear through normalization. PostgreSQL JSON/text cannot contain NUL.
 for i in 1..char_length(t) loop
   cp:=ascii(substr(t,i,1));
   if cp between 0 and 31 or cp=127 or (not p_legacy and (cp between 128 and 159 or cp in (8232,8233))) then return false; end if;
 end loop;
 t:=nullif(btrim(t,U&'\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'),'');
 return app.storefront_content_text_v1(t,p_max,p_legacy);
end; $$;
create function app.storefront_content_trim_v1(p_value jsonb)
returns text language sql immutable set search_path='' as $$
 select nullif(btrim(p_value#>>'{}',U&'\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'),'');
$$;
create function app.storefront_content_text_array_v1(p_values text[],p_min integer,p_max integer,p_each integer,p_total integer)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_values is not null and cardinality(p_values) between p_min and p_max
   and (cardinality(p_values)=0 or (array_ndims(p_values)=1 and array_lower(p_values,1)=1))
   and not exists(select 1 from unnest(p_values) x(v) where v is null or not app.storefront_content_text_v1(v,p_each,false))
   and coalesce((select sum(char_length(v)) from unnest(p_values) x(v)),0)<=p_total,false);
$$;
create function app.storefront_content_document_shape_v1(p_document jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare
 d jsonb:=p_document; h jsonb; f jsonb; x jsonb; row_value jsonb; a jsonb;
 k text; value_text text; expected text[]; ids text[]; array_key text;
 s integer; e integer; b integer; headline text; max_len integer;
 c_fields constant text[]:=array['hero_headline','hero_subline','announcement_text','hero','announcement_segments','promo','story','category_presentation','item_presentation'];
begin
 if jsonb_typeof(d) is distinct from 'object' then return jsonb_build_object('error','document_not_object','field','document'); end if;
 if octet_length(d::text)>262144 then return jsonb_build_object('error','document_too_large','field','document'); end if;
 if not app.storefront_content_keys_v1(d,c_fields) then
   if not d ?& c_fields then return jsonb_build_object('error','missing_field','field','document'); end if;
   return jsonb_build_object('error','unknown_field','field','document');
 end if;
 foreach k in array array['hero_headline','hero_subline','announcement_text'] loop
   max_len:=case k when 'hero_headline' then 120 when 'hero_subline' then 180 else 240 end;
   if not app.storefront_content_input_text_v1(d->k,max_len,true) then return jsonb_build_object('error','text_invalid','field',k); end if;
   d:=jsonb_set(d,array[k],coalesce(to_jsonb(app.storefront_content_trim_v1(d->k)),'null'::jsonb));
 end loop;
 headline:=d->>'hero_headline'; h:=d->'hero';
 if not app.storefront_content_keys_v1(h,array['mode','item_id','format','eyebrow','stamp','footnote'])
   or jsonb_typeof(h->'mode') is distinct from 'string' or h->>'mode' not in ('editorial','item') then
   return jsonb_build_object('error','presentation_invalid','field','hero');
 end if;
 if h->'item_id'<>'null'::jsonb and not app.storefront_content_uuid_v1(h->'item_id') then return jsonb_build_object('error','target_invalid','field','hero.item_id'); end if;
 if h->>'mode'='item' and h->'item_id'='null'::jsonb then return jsonb_build_object('error','target_invalid','field','hero.item_id'); end if;
 foreach k in array array['eyebrow','stamp','footnote'] loop
   max_len:=case k when 'eyebrow' then 60 when 'stamp' then 80 else 120 end;
   if not app.storefront_content_input_text_v1(h->k,max_len,false) then return jsonb_build_object('error','text_invalid','field','hero.'||k); end if;
   h:=jsonb_set(h,array[k],coalesce(to_jsonb(app.storefront_content_trim_v1(h->k)),'null'::jsonb));
 end loop;
 f:=h->'format'; s:=null;e:=null;b:=null;
 if f<>'null'::jsonb then
   if not app.storefront_content_keys_v1(f,array['text','highlight','break_before']) or jsonb_typeof(f->'text') is distinct from 'string'
     or convert_to(f->>'text','UTF8') is distinct from convert_to(headline,'UTF8') then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
   if f->'highlight'<>'null'::jsonb then
     x:=f->'highlight';
     if not app.storefront_content_keys_v1(x,array['start','end']) or jsonb_typeof(x->'start') is distinct from 'number' or jsonb_typeof(x->'end') is distinct from 'number' then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     if (x->>'start')::numeric<>trunc((x->>'start')::numeric) or (x->>'end')::numeric<>trunc((x->>'end')::numeric) or (x->>'start')::numeric not between 0 and 120 or (x->>'end')::numeric not between 0 and 120 then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     s:=(x->>'start')::integer;e:=(x->>'end')::integer;
   end if;
   if f->'break_before'<>'null'::jsonb then
     if jsonb_typeof(f->'break_before') is distinct from 'number' then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     if (f->>'break_before')::numeric<>trunc((f->>'break_before')::numeric) or (f->>'break_before')::numeric not between 0 and 120 then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
     b:=(f->>'break_before')::integer;
   end if;
   if not app.storefront_content_hero_format_valid_v1(headline,s,e,b) then return jsonb_build_object('error','headline_format_invalid','field','hero.format'); end if;
   if s is null and b is null then h:=jsonb_set(h,'{format}','null'); end if;
 end if;
 d:=jsonb_set(d,'{hero}',h);
 if d->'announcement_segments'<>'null'::jsonb then
   if jsonb_typeof(d->'announcement_segments') is distinct from 'array' then return jsonb_build_object('error','segments_invalid','field','announcement_segments'); end if;
   a:='[]';
   for x in select value from jsonb_array_elements(d->'announcement_segments') loop
     if x='null'::jsonb or not app.storefront_content_input_text_v1(x,40,false) or app.storefront_content_trim_v1(x) is null then return jsonb_build_object('error','segments_invalid','field','announcement_segments'); end if;
     a:=a||jsonb_build_array(app.storefront_content_trim_v1(x));
   end loop;
   if jsonb_array_length(a)>6 or (select coalesce(sum(char_length(v)),0) from jsonb_array_elements_text(a) x(v))>240 then return jsonb_build_object('error','segments_invalid','field','announcement_segments'); end if;
   d:=jsonb_set(d,'{announcement_segments}',case when jsonb_array_length(a)=0 then 'null'::jsonb else a end);
 end if;
 foreach array_key in array array['promo','story'] loop
   x:=d->array_key;
   if x='null'::jsonb then continue; end if;
   if array_key='story' then expected:=array['kicker','title','body','editorial_media_id','facts'];
   elsif x#>>'{target,kind}'='category' then expected:=array['target','kicker','title','body','editorial_media_id'];
   else expected:=array['target','kicker','title','body']; end if;
   if not app.storefront_content_keys_v1(x,expected) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
   foreach k in array array['kicker','title','body'] loop
     max_len:=case k when 'kicker' then 60 when 'title' then 120 else 600 end;
     if x->k='null'::jsonb or not app.storefront_content_input_text_v1(x->k,max_len,false) or app.storefront_content_trim_v1(x->k) is null then return jsonb_build_object('error','text_invalid','field',array_key); end if;
     x:=jsonb_set(x,array[k],to_jsonb(app.storefront_content_trim_v1(x->k)));
   end loop;
   if array_key='story' or x#>>'{target,kind}'='category' then
     if not app.storefront_content_uuid_v1(x->'editorial_media_id') then return jsonb_build_object('error','media_invalid','field',array_key||'.editorial_media_id'); end if;
   end if;
   if array_key='story' then
     if jsonb_typeof(x->'facts') is distinct from 'array' then return jsonb_build_object('error','presentation_invalid','field','story'); end if;
     if jsonb_array_length(x->'facts')>3 then return jsonb_build_object('error','presentation_invalid','field','story'); end if;
     a:='[]';for row_value in select value from jsonb_array_elements(x->'facts') loop
       if row_value='null'::jsonb or not app.storefront_content_input_text_v1(row_value,80,false) or app.storefront_content_trim_v1(row_value) is null then return jsonb_build_object('error','text_invalid','field','story'); end if;
       a:=a||jsonb_build_array(app.storefront_content_trim_v1(row_value));
     end loop;x:=jsonb_set(x,'{facts}',a);
   elsif x#>>'{target,kind}'='category' then
     if not app.storefront_content_keys_v1(x->'target',array['kind','category_id']) or not app.storefront_content_uuid_v1(x#>'{target,category_id}') then return jsonb_build_object('error','target_invalid','field','promo.target'); end if;
   elsif x#>>'{target,kind}'='item' then
     if not app.storefront_content_keys_v1(x->'target',array['kind','item_id']) or not app.storefront_content_uuid_v1(x#>'{target,item_id}') then return jsonb_build_object('error','target_invalid','field','promo.target'); end if;
   else return jsonb_build_object('error','target_invalid','field','promo.target'); end if;
   d:=jsonb_set(d,array[array_key],x);
 end loop;
 foreach array_key in array array['category_presentation','item_presentation'] loop
   if jsonb_typeof(d->array_key) is distinct from 'array' then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
    if jsonb_array_length(d->array_key)>(case array_key when 'category_presentation' then 100 else 500 end) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
   ids:='{}';a:='[]';
   for x in select value from jsonb_array_elements(d->array_key) loop
     if array_key='category_presentation' then expected:=array['category_id','heading','blurb','editorial_media_id','image_fit','card_layout'];k:='category_id';
     else expected:=array['item_id','image_fit','card_layout'];k:='item_id';end if;
     if not app.storefront_content_keys_v1(x,expected) or not app.storefront_content_uuid_v1(x->k) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
     if x->>k=any(ids) then return jsonb_build_object('error','duplicate_id','field',array_key); end if;ids:=array_append(ids,x->>k);
     if not (x->'image_fit'='null'::jsonb or (jsonb_typeof(x->'image_fit')='string' and x->>'image_fit' in ('fill','whole-image')))
       or not (x->'card_layout'='null'::jsonb or (jsonb_typeof(x->'card_layout')='string' and x->>'card_layout' in ('standard','cutout'))) then return jsonb_build_object('error','presentation_invalid','field',array_key); end if;
     if array_key='category_presentation' then
       if x->'editorial_media_id'<>'null'::jsonb and not app.storefront_content_uuid_v1(x->'editorial_media_id') then return jsonb_build_object('error','media_invalid','field','category_presentation'); end if;
       foreach k in array array['heading','blurb'] loop
         if not app.storefront_content_input_text_v1(x->k,case k when 'heading' then 80 else 120 end,false) then return jsonb_build_object('error','text_invalid','field','category_presentation'); end if;
         x:=jsonb_set(x,array[k],coalesce(to_jsonb(app.storefront_content_trim_v1(x->k)),'null'::jsonb));
       end loop;
     end if;
     a:=a||jsonb_build_array(x);
   end loop;d:=jsonb_set(d,array[array_key],a);
 end loop;
 return jsonb_build_object('document',d);
end; $$;

alter table public.menu_categories add constraint storefront_content_categories_scope_unique unique(organization_id,restaurant_id,id);
alter table public.menu_items add constraint storefront_content_items_scope_unique unique(organization_id,restaurant_id,id);
alter table public.storefront_media add constraint storefront_content_media_scope_unique unique(organization_id,restaurant_id,id);
create table app.storefront_content_profiles (
 organization_id uuid not null,restaurant_id uuid not null,storefront_branch_id uuid not null,
 hero_mode text not null default 'editorial' check(hero_mode in ('editorial','item')),hero_item_id uuid,
 headline_format_text text,headline_highlight_start integer,headline_highlight_end integer,headline_break_before integer,
 hero_eyebrow text check(app.storefront_content_text_v1(hero_eyebrow,60,false)),
 hero_stamp text check(app.storefront_content_text_v1(hero_stamp,80,false)),
 hero_footnote text check(app.storefront_content_text_v1(hero_footnote,120,false)),
 announcement_segments text[] check(announcement_segments is null or app.storefront_content_text_array_v1(announcement_segments,1,6,40,240)),
 promo_kind text check(promo_kind in ('category','item')),promo_category_id uuid,promo_item_id uuid,promo_media_id uuid,
 promo_kicker text check(app.storefront_content_text_v1(promo_kicker,60,false)),promo_title text check(app.storefront_content_text_v1(promo_title,120,false)),promo_body text check(app.storefront_content_text_v1(promo_body,600,false)),
 story_media_id uuid,story_kicker text check(app.storefront_content_text_v1(story_kicker,60,false)),story_title text check(app.storefront_content_text_v1(story_title,120,false)),story_body text check(app.storefront_content_text_v1(story_body,600,false)),
 story_facts text[] not null default '{}' check(app.storefront_content_text_array_v1(story_facts,0,3,80,240)),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),deleted_at timestamptz,
 primary key(organization_id,restaurant_id,storefront_branch_id),
 foreign key(organization_id,restaurant_id) references public.restaurant_storefront_profiles(organization_id,restaurant_id) on delete restrict,
 foreign key(organization_id,restaurant_id,storefront_branch_id) references public.branches(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,hero_item_id) references public.menu_items(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,promo_item_id) references public.menu_items(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,promo_category_id) references public.menu_categories(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,promo_media_id) references public.storefront_media(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,story_media_id) references public.storefront_media(organization_id,restaurant_id,id) on delete restrict,
 check(hero_mode<>'item' or hero_item_id is not null),
 check((headline_format_text is null and headline_highlight_start is null and headline_highlight_end is null and headline_break_before is null)
   or (headline_format_text is not null and (headline_highlight_start is not null or headline_break_before is not null)
     and app.storefront_content_hero_format_valid_v1(headline_format_text,headline_highlight_start,headline_highlight_end,headline_break_before))),
 check(coalesce((promo_kind is null and promo_category_id is null and promo_item_id is null and promo_media_id is null and promo_kicker is null and promo_title is null and promo_body is null)
   or (promo_kind='category' and promo_category_id is not null and promo_item_id is null and promo_media_id is not null and promo_kicker is not null and promo_title is not null and promo_body is not null)
   or (promo_kind='item' and promo_item_id is not null and promo_category_id is null and promo_media_id is null and promo_kicker is not null and promo_title is not null and promo_body is not null),false)),
 check((story_media_id is null and story_kicker is null and story_title is null and story_body is null and cardinality(story_facts)=0)
   or (story_media_id is not null and story_kicker is not null and story_title is not null and story_body is not null))
);
create table app.storefront_category_presentation (
 organization_id uuid not null,restaurant_id uuid not null,storefront_branch_id uuid not null,category_id uuid not null,
 heading text check(app.storefront_content_text_v1(heading,80,false)),blurb text check(app.storefront_content_text_v1(blurb,120,false)),editorial_media_id uuid,
 image_fit text check(image_fit in ('fill','whole-image')),card_layout text check(card_layout in ('standard','cutout')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),deleted_at timestamptz,
 primary key(organization_id,restaurant_id,storefront_branch_id,category_id),
 foreign key(organization_id,restaurant_id,storefront_branch_id) references app.storefront_content_profiles(organization_id,restaurant_id,storefront_branch_id) on delete restrict,
 foreign key(organization_id,restaurant_id,category_id) references public.menu_categories(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,editorial_media_id) references public.storefront_media(organization_id,restaurant_id,id) on delete restrict
);
create table app.storefront_item_presentation (
 organization_id uuid not null,restaurant_id uuid not null,storefront_branch_id uuid not null,item_id uuid not null,
 image_fit text check(image_fit in ('fill','whole-image')),card_layout text check(card_layout in ('standard','cutout')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),deleted_at timestamptz,
 primary key(organization_id,restaurant_id,storefront_branch_id,item_id),
 foreign key(organization_id,restaurant_id,storefront_branch_id) references app.storefront_content_profiles(organization_id,restaurant_id,storefront_branch_id) on delete restrict,
 foreign key(organization_id,restaurant_id,item_id) references public.menu_items(organization_id,restaurant_id,id) on delete restrict
);
do $$ declare t text;begin
 foreach t in array array['storefront_content_profiles','storefront_category_presentation','storefront_item_presentation'] loop
  execute format('alter table app.%I enable row level security',t);execute format('alter table app.%I force row level security',t);
  execute format('revoke all on table app.%I from public,anon,authenticated,service_role',t);
  execute format('create policy content_select_deny on app.%I for select to authenticated using(false)',t);
  execute format('create policy content_insert_deny on app.%I for insert to authenticated with check(false)',t);
  execute format('create policy content_update_deny on app.%I for update to authenticated using(false) with check(false)',t);
  execute format('create policy content_delete_deny on app.%I for delete to authenticated using(false)',t);
  execute format('create trigger content_set_updated_at before update on app.%I for each row execute function app.set_updated_at()',t);
 end loop;
end; $$;

create function app.storefront_content_media_url_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_media uuid)
returns text language sql stable set search_path='' as $$
 select '/storage/v1/object/public/storefront-media/'||m.object_key
 from public.storefront_media m
 where m.id=p_media and m.organization_id=p_org and m.restaurant_id=p_restaurant
  and m.variant='w960' and m.published_at is not null and m.unpublished_at is null
  and exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=m.object_key
    and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=m.bytes::text)
  and ((m.source_bucket='menu-images' and exists(select 1 from storage.objects o cross join lateral app.menu_image_scope(o.name) s
    where o.bucket_id=m.source_bucket and o.name=m.source_key and s.organization_id=p_org and s.restaurant_id=p_restaurant and (s.branch_id is null or s.branch_id=p_branch)))
   or (m.source_bucket='restaurant-logos' and exists(select 1 from storage.objects o cross join lateral app.restaurant_logo_scope(o.name) s
    where o.bucket_id=m.source_bucket and o.name=m.source_key and s.organization_id=p_org and s.restaurant_id=p_restaurant)));
$$;
-- Private eligibility for an unpublished editor. Public v4 NEVER calls this
-- catalogue helper: it intersects only the single served v3 snapshot instead.
create function app.storefront_content_catalog_v1(p_org uuid,p_restaurant uuid,p_branch uuid)
returns jsonb language sql stable set search_path='' as $$
 with eligible as (
  select i.id,i.menu_category_id,i.display_order,i.name,coalesce(a.availability,'available') availability,
   case when m.id is null then null else '/storage/v1/object/public/storefront-media/'||m.object_key end image_url
  from public.menu_items i join public.menu_categories c on c.organization_id=i.organization_id and c.restaurant_id=i.restaurant_id and c.id=i.menu_category_id
  left join public.menu_item_branch_availability a on a.organization_id=i.organization_id and a.branch_id=p_branch and a.menu_item_id=i.id
  left join public.storefront_media m on m.organization_id=i.organization_id and m.restaurant_id=i.restaurant_id and m.source_bucket='menu-images'
   and m.source_key=i.image_path and m.variant='w480' and m.published_at is not null and m.unpublished_at is null
   and exists(select 1 from app.menu_image_scope(m.source_key) s where s.menu_item_id=i.id and s.branch_id is not distinct from i.branch_id)
   and m.item_source_snapshot=app.storefront_item_source_snapshot(i.organization_id,i.restaurant_id,i.image_path)
   and exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=m.object_key and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=m.bytes::text)
  where i.organization_id=p_org and i.restaurant_id=p_restaurant and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id=p_branch)
   and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id=p_branch)
 ) select jsonb_build_object(
  'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'category_id',i.menu_category_id,'availability',i.availability,'image_url',i.image_url) order by i.display_order,i.name,i.id) from eligible i),'[]'::jsonb),
  'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id) order by c.display_order,c.name,c.id) from public.menu_categories c
    where c.organization_id=p_org and c.restaurant_id=p_restaurant and exists(select 1 from eligible i where i.menu_category_id=c.id)),'[]'::jsonb));
$$;
create function app.storefront_content_item_member_v1(p_catalog jsonb,p_id uuid,p_promo boolean default false)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(exists(select 1 from jsonb_array_elements(p_catalog->'items') x(i)
  where i->>'id'=p_id::text and exists(select 1 from jsonb_array_elements(p_catalog->'categories') y(c) where c->>'id'=i->>'category_id')
   and (not p_promo or (i->>'availability'='available' and i->>'image_url' is not null))),false);
$$;
create function app.storefront_content_category_member_v1(p_catalog jsonb,p_id uuid)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(exists(select 1 from jsonb_array_elements(p_catalog->'categories') x(c) where c->>'id'=p_id::text
  and exists(select 1 from jsonb_array_elements(p_catalog->'items') y(i) where i->>'category_id'=c->>'id')),false);
$$;
create function app.storefront_content_read_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_headline text,p_subline text,p_announcement text,p_catalog jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare r app.storefront_content_profiles%rowtype; cr app.storefront_category_presentation%rowtype;
 ir app.storefront_item_presentation%rowtype; h jsonb; f jsonb:='null';promo jsonb:='null';story jsonb:='null';cats jsonb:='[]';items jsonb:='[]';warnings jsonb:='[]';
 hero_id uuid;hero_mode text;url text;heading text;blurb text;fit text;layout text;media_id uuid;entry jsonb;v_doc jsonb;
begin
 select * into r from app.storefront_content_profiles c where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null;
 hero_mode:=case when r.hero_mode in ('editorial','item') then r.hero_mode else 'editorial' end;
 hero_id:=r.hero_item_id;
 if (hero_mode='item' and hero_id is null) or (hero_id is not null and not app.storefront_content_item_member_v1(p_catalog,hero_id)) then
  hero_id:=null;hero_mode:='editorial';warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.item_id','reason','relation_unavailable'));
 end if;
 if r.headline_format_text is not null then
  if convert_to(r.headline_format_text,'UTF8') is not distinct from convert_to(p_headline,'UTF8')
   and app.storefront_content_hero_format_valid_v1(p_headline,r.headline_highlight_start,r.headline_highlight_end,r.headline_break_before) then
   f:=jsonb_build_object('text',p_headline,'highlight',case when r.headline_highlight_start is null then 'null'::jsonb else jsonb_build_object('start',r.headline_highlight_start,'end',r.headline_highlight_end) end,'break_before',r.headline_break_before);
  else warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.format','reason','legacy_value_invalid'));end if;
 end if;
 h:=jsonb_build_object('mode',hero_mode,'item_id',hero_id,'format',f,
  'eyebrow',case when app.storefront_content_text_v1(r.hero_eyebrow,60,false) then r.hero_eyebrow end,
  'stamp',case when app.storefront_content_text_v1(r.hero_stamp,80,false) then r.hero_stamp end,
  'footnote',case when app.storefront_content_text_v1(r.hero_footnote,120,false) then r.hero_footnote end);
 if not app.storefront_content_text_v1(r.hero_eyebrow,60,false) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.eyebrow','reason','legacy_value_invalid'));end if;
 if not app.storefront_content_text_v1(r.hero_stamp,80,false) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.stamp','reason','legacy_value_invalid'));end if;
 if not app.storefront_content_text_v1(r.hero_footnote,120,false) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','hero.footnote','reason','legacy_value_invalid'));end if;
 if r.announcement_segments is not null and not app.storefront_content_text_array_v1(r.announcement_segments,1,6,40,240) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','announcement_segments','reason','legacy_value_invalid'));end if;
 if r.promo_kind is not null then
  if r.promo_kicker is not null and r.promo_title is not null and r.promo_body is not null
    and app.storefront_content_text_v1(r.promo_kicker,60,false) and app.storefront_content_text_v1(r.promo_title,120,false) and app.storefront_content_text_v1(r.promo_body,600,false) then
   if r.promo_kind='category' and app.storefront_content_category_member_v1(p_catalog,r.promo_category_id)
     and app.storefront_content_media_url_v1(p_org,p_restaurant,p_branch,r.promo_media_id) is not null then
    promo:=jsonb_build_object('target',jsonb_build_object('kind','category','category_id',r.promo_category_id),'kicker',r.promo_kicker,'title',r.promo_title,'body',r.promo_body,'editorial_media_id',r.promo_media_id);
   elsif r.promo_kind='item' and app.storefront_content_item_member_v1(p_catalog,r.promo_item_id,true) then
    promo:=jsonb_build_object('target',jsonb_build_object('kind','item','item_id',r.promo_item_id),'kicker',r.promo_kicker,'title',r.promo_title,'body',r.promo_body);
   end if;
  end if;
  if promo='null'::jsonb then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','promo','reason','relation_unavailable'));end if;
 end if;
 if r.story_media_id is not null then
  if app.storefront_content_media_url_v1(p_org,p_restaurant,p_branch,r.story_media_id) is not null
    and r.story_kicker is not null and r.story_title is not null and r.story_body is not null
    and app.storefront_content_text_v1(r.story_kicker,60,false) and app.storefront_content_text_v1(r.story_title,120,false) and app.storefront_content_text_v1(r.story_body,600,false)
    and app.storefront_content_text_array_v1(r.story_facts,0,3,80,240) then
   story:=jsonb_build_object('kicker',r.story_kicker,'title',r.story_title,'body',r.story_body,'editorial_media_id',r.story_media_id,'facts',r.story_facts);
  else warnings:=warnings||jsonb_build_array(jsonb_build_object('field','story','reason','media_unavailable'));end if;
 end if;
 if exists(select 1 from app.storefront_category_presentation c where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null and not app.storefront_content_category_member_v1(p_catalog,c.category_id)) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','category_presentation','reason','relation_unavailable'));end if;
 if exists(select 1 from app.storefront_item_presentation i where i.organization_id=p_org and i.restaurant_id=p_restaurant and i.storefront_branch_id=p_branch and i.deleted_at is null and not app.storefront_content_item_member_v1(p_catalog,i.item_id)) then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','item_presentation','reason','relation_unavailable'));end if;
 for cr in select c.* from app.storefront_category_presentation c join jsonb_array_elements(p_catalog->'categories') with ordinality x(v,n) on x.v->>'id'=c.category_id::text
  where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null order by x.n loop
  if not app.storefront_content_category_member_v1(p_catalog,cr.category_id) then continue;end if;
  heading:=case when app.storefront_content_text_v1(cr.heading,80,false) then cr.heading end;blurb:=case when app.storefront_content_text_v1(cr.blurb,120,false) then cr.blurb end;
  fit:=case when cr.image_fit in ('fill','whole-image') then cr.image_fit end;layout:=case when cr.card_layout in ('standard','cutout') then cr.card_layout end;
  media_id:=case when app.storefront_content_media_url_v1(p_org,p_restaurant,p_branch,cr.editorial_media_id) is not null then cr.editorial_media_id end;
  if cr.editorial_media_id is not null and media_id is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('field','category_presentation','reason','media_unavailable'));end if;
  if heading is not null or blurb is not null or media_id is not null or fit is not null or layout is not null then
   cats:=cats||jsonb_build_array(jsonb_build_object('category_id',cr.category_id,'heading',heading,'blurb',blurb,'editorial_media_id',media_id,'image_fit',fit,'card_layout',layout));
  end if;
 end loop;
 for ir in select i.* from app.storefront_item_presentation i join jsonb_array_elements(p_catalog->'items') with ordinality x(v,n) on x.v->>'id'=i.item_id::text
  where i.organization_id=p_org and i.restaurant_id=p_restaurant and i.storefront_branch_id=p_branch and i.deleted_at is null order by x.n loop
  if not app.storefront_content_item_member_v1(p_catalog,ir.item_id) then continue;end if;
  fit:=case when ir.image_fit in ('fill','whole-image') then ir.image_fit end;layout:=case when ir.card_layout in ('standard','cutout') then ir.card_layout end;
  if fit is not null or layout is not null then items:=items||jsonb_build_array(jsonb_build_object('item_id',ir.item_id,'image_fit',fit,'card_layout',layout));end if;
 end loop;
 -- Warnings never echo IDs, indexes, keys, source paths or caller values.
 select coalesce(jsonb_agg(v order by v->>'field',v->>'reason'),'[]'::jsonb) into warnings from (select distinct v from jsonb_array_elements(warnings) x(v)) q;
 v_doc:=jsonb_build_object('hero_headline',p_headline,'hero_subline',p_subline,'announcement_text',p_announcement,'hero',h,
  'announcement_segments',case when app.storefront_content_text_array_v1(r.announcement_segments,1,6,40,240) then to_jsonb(r.announcement_segments) else 'null'::jsonb end,
  'promo',promo,'story',story,'category_presentation',cats,'item_presentation',items);
 return jsonb_build_object('document',v_doc,'warnings',warnings);
end; $$;

create function app.get_restaurant_storefront_content_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.restaurant_storefront_profiles%rowtype;v jsonb;actor_rank integer;
begin
 if app.current_app_user_id() is null then raise exception 'storefront content authentication required' using errcode='42501';end if;
 if p_organization_id is null or p_restaurant_id is null or not exists(select 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null) then raise exception 'storefront content scope denied' using errcode='42501';end if;
 actor_rank:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null);
 if actor_rank=0 then raise exception 'storefront content authority denied' using errcode='42501';end if;
 if actor_rank<2 then return jsonb_build_object('ok',false,'error','not_found','entity','restaurant_storefront_content');end if;
 select * into p from public.restaurant_storefront_profiles where organization_id=p_organization_id and restaurant_id=p_restaurant_id and deleted_at is null;
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity','restaurant_storefront_content');end if;
 v:=app.storefront_content_read_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,p.hero_headline,p.hero_subline,p.announcement_text,app.storefront_content_catalog_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id));
 return jsonb_build_object('ok',true,'entity','restaurant_storefront_content','restaurant_id',p_restaurant_id,'version',p.version,'storefront_branch_id',p.storefront_branch_id,'document',v->'document','warnings',v->'warnings');
end; $$;
create function public.get_restaurant_storefront_content_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$select app.get_restaurant_storefront_content_v1(p_organization_id,p_restaurant_id);$$;

create function app.set_restaurant_storefront_content_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_version integer,p_expected_storefront_branch_id uuid,p_document jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();rank_value integer;p public.restaurant_storefront_profiles%rowtype;
 fp text;replay jsonb;result jsonb;parsed jsonb;d jsonb;h jsonb;f jsonb;v jsonb;catalog jsonb;old_doc jsonb;new_doc jsonb;
 c_entity constant text:='restaurant_storefront_content';c_operation constant text:='set_restaurant_storefront_content_v1';
begin
 if actor is null then raise exception 'storefront content authentication required' using errcode='42501';end if;
 if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_expected_version is null or p_expected_version<0 or p_expected_storefront_branch_id is null then raise exception 'storefront content required input denied' using errcode='42501';end if;
 -- Check ancestry BEFORE rank1's audit, so a covering org actor cannot place
 -- an audit event under a restaurant from a different organization.
 if not exists(select 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null) then raise exception 'storefront content scope denied' using errcode='42501';end if;
 rank_value:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null);
 if rank_value=0 then raise exception 'storefront content authority denied' using errcode='42501';end if;
 if rank_value<2 then
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.content.denied',null,jsonb_build_object('setting','storefront_content'));
  return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);
 end if;
 perform 1 from public.restaurants r where r.id=p_restaurant_id and r.organization_id=p_organization_id and r.deleted_at is null for update;
 if not found then raise exception 'storefront content scope changed' using errcode='42501';end if;
 select * into p from public.restaurant_storefront_profiles where organization_id=p_organization_id and restaurant_id=p_restaurant_id and deleted_at is null for update;
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity',c_entity);end if;
 perform 1 from app.storefront_content_profiles c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id order by c.storefront_branch_id for update;
 perform 1 from app.storefront_category_presentation c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id order by c.storefront_branch_id,c.category_id for update;
 perform 1 from app.storefront_item_presentation i where i.organization_id=p_organization_id and i.restaurant_id=p_restaurant_id order by i.storefront_branch_id,i.item_id for update;
 perform 1 from public.storefront_media m where m.organization_id=p_organization_id and m.restaurant_id=p_restaurant_id order by m.id for update;
 if app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null)<2 then raise exception 'storefront content authority changed' using errcode='42501';end if;
 fp:=md5(jsonb_build_object('org',p_organization_id,'restaurant',p_restaurant_id,'expected_version',p_expected_version,'expected_branch',p_expected_storefront_branch_id,'document',p_document)::text);
 replay:=app.management_idem_check(actor,p_client_request_id,c_operation,fp);
 if replay is not null then return replay;end if;
 -- Exact replay precedes NEW-request branch/CAS validation. It never restores
 -- old branch settings after a later branch change or content save.
 if p.storefront_branch_id<>p_expected_storefront_branch_id then return jsonb_build_object('ok',false,'error','branch_conflict','entity',c_entity,'version',p.version);end if;
 if p.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict','entity',c_entity,'restaurant_id',p_restaurant_id,'version',p.version,'slug',p.slug,'is_published',p.is_published);end if;
 parsed:=app.storefront_content_document_shape_v1(p_document);
 if parsed ? 'error' then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason',parsed->>'error','field',parsed->>'field');end if;
 d:=parsed->'document';h:=d->'hero';f:=h->'format';
 if not exists(select 1 from public.branches b where b.id=p.storefront_branch_id and b.organization_id=p_organization_id and b.restaurant_id=p_restaurant_id and b.status='active' and b.deleted_at is null) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','document');end if;
 catalog:=app.storefront_content_catalog_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id);
 if h->>'item_id' is not null and not app.storefront_content_item_member_v1(catalog,(h->>'item_id')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','hero.item_id');end if;
 if d->'promo'<>'null'::jsonb then
  v:=d->'promo';
  if v#>>'{target,kind}'='category' then
   if not app.storefront_content_category_member_v1(catalog,(v#>>'{target,category_id}')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','promo.target');end if;
   if app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'editorial_media_id')::uuid) is null then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','promo.editorial_media_id');end if;
  elsif not app.storefront_content_item_member_v1(catalog,(v#>>'{target,item_id}')::uuid,true) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','promo.target');end if;
 end if;
 if d->'story'<>'null'::jsonb and app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(d#>>'{story,editorial_media_id}')::uuid) is null then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','story.editorial_media_id');end if;
 for v in select value from jsonb_array_elements(d->'category_presentation') loop
  if not app.storefront_content_category_member_v1(catalog,(v->>'category_id')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','category_presentation');end if;
  if v->>'editorial_media_id' is not null and app.storefront_content_media_url_v1(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'editorial_media_id')::uuid) is null then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','media_invalid','field','category_presentation');end if;
 end loop;
 for v in select value from jsonb_array_elements(d->'item_presentation') loop
  if not app.storefront_content_item_member_v1(catalog,(v->>'item_id')::uuid) then return jsonb_build_object('ok',false,'error','invalid','entity',c_entity,'reason','target_invalid','field','item_presentation');end if;
 end loop;
 result:=jsonb_build_object('ok',true,'idempotent_replay',false,'entity',c_entity,'restaurant_id',p_restaurant_id,'version',p.version+1,'slug',p.slug,'is_published',p.is_published);
 replay:=app.management_claim_request(actor,p_client_request_id,c_operation,fp,result);if replay is not null then return replay;end if;
 old_doc:=app.get_restaurant_storefront_content_v1(p_organization_id,p_restaurant_id)->'document';
 -- Existing writer compatibility trigger clears OLD formatting first. The new
 -- validated tuple is installed only afterward, in this same transaction.
 update public.restaurant_storefront_profiles set hero_headline=d->>'hero_headline',hero_subline=d->>'hero_subline',announcement_text=d->>'announcement_text',version=p.version+1
  where organization_id=p_organization_id and restaurant_id=p_restaurant_id;
 insert into app.storefront_content_profiles(organization_id,restaurant_id,storefront_branch_id,hero_mode,hero_item_id,headline_format_text,headline_highlight_start,headline_highlight_end,headline_break_before,hero_eyebrow,hero_stamp,hero_footnote,announcement_segments,
  promo_kind,promo_category_id,promo_item_id,promo_media_id,promo_kicker,promo_title,promo_body,story_media_id,story_kicker,story_title,story_body,story_facts)
 values(p_organization_id,p_restaurant_id,p.storefront_branch_id,h->>'mode',(h->>'item_id')::uuid,f->>'text',(f#>>'{highlight,start}')::integer,(f#>>'{highlight,end}')::integer,(f->>'break_before')::integer,h->>'eyebrow',h->>'stamp',h->>'footnote',
  case when d->'announcement_segments'='null'::jsonb then null else array(select jsonb_array_elements_text(d->'announcement_segments')) end,
  d#>>'{promo,target,kind}',(d#>>'{promo,target,category_id}')::uuid,(d#>>'{promo,target,item_id}')::uuid,(d#>>'{promo,editorial_media_id}')::uuid,d#>>'{promo,kicker}',d#>>'{promo,title}',d#>>'{promo,body}',
  (d#>>'{story,editorial_media_id}')::uuid,d#>>'{story,kicker}',d#>>'{story,title}',d#>>'{story,body}',case when d->'story'='null'::jsonb then '{}'::text[] else array(select jsonb_array_elements_text(d#>'{story,facts}')) end)
 on conflict(organization_id,restaurant_id,storefront_branch_id) do update set hero_mode=excluded.hero_mode,hero_item_id=excluded.hero_item_id,
  headline_format_text=excluded.headline_format_text,headline_highlight_start=excluded.headline_highlight_start,headline_highlight_end=excluded.headline_highlight_end,headline_break_before=excluded.headline_break_before,
  hero_eyebrow=excluded.hero_eyebrow,hero_stamp=excluded.hero_stamp,hero_footnote=excluded.hero_footnote,announcement_segments=excluded.announcement_segments,
  promo_kind=excluded.promo_kind,promo_category_id=excluded.promo_category_id,promo_item_id=excluded.promo_item_id,promo_media_id=excluded.promo_media_id,promo_kicker=excluded.promo_kicker,promo_title=excluded.promo_title,promo_body=excluded.promo_body,
  story_media_id=excluded.story_media_id,story_kicker=excluded.story_kicker,story_title=excluded.story_title,story_body=excluded.story_body,story_facts=excluded.story_facts,deleted_at=null;
 update app.storefront_category_presentation c set deleted_at=now() where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id and c.storefront_branch_id=p.storefront_branch_id and c.deleted_at is null
  and not exists(select 1 from jsonb_array_elements(d->'category_presentation') x(v) where x.v->>'category_id'=c.category_id::text);
 for v in select value from jsonb_array_elements(d->'category_presentation') loop
  insert into app.storefront_category_presentation(organization_id,restaurant_id,storefront_branch_id,category_id,heading,blurb,editorial_media_id,image_fit,card_layout)
  values(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'category_id')::uuid,v->>'heading',v->>'blurb',(v->>'editorial_media_id')::uuid,v->>'image_fit',v->>'card_layout')
  on conflict(organization_id,restaurant_id,storefront_branch_id,category_id) do update set heading=excluded.heading,blurb=excluded.blurb,editorial_media_id=excluded.editorial_media_id,image_fit=excluded.image_fit,card_layout=excluded.card_layout,deleted_at=null;
 end loop;
 update app.storefront_item_presentation i set deleted_at=now() where i.organization_id=p_organization_id and i.restaurant_id=p_restaurant_id and i.storefront_branch_id=p.storefront_branch_id and i.deleted_at is null
  and not exists(select 1 from jsonb_array_elements(d->'item_presentation') x(v) where x.v->>'item_id'=i.item_id::text);
 for v in select value from jsonb_array_elements(d->'item_presentation') loop
  insert into app.storefront_item_presentation(organization_id,restaurant_id,storefront_branch_id,item_id,image_fit,card_layout)
  values(p_organization_id,p_restaurant_id,p.storefront_branch_id,(v->>'item_id')::uuid,v->>'image_fit',v->>'card_layout')
  on conflict(organization_id,restaurant_id,storefront_branch_id,item_id) do update set image_fit=excluded.image_fit,card_layout=excluded.card_layout,deleted_at=null;
 end loop;
 new_doc:=app.get_restaurant_storefront_content_v1(p_organization_id,p_restaurant_id)->'document';
 perform app.management_audit(p_organization_id,p_restaurant_id,p.storefront_branch_id,'settings.storefront.content.updated',old_doc,new_doc);
 return result;
end; $$;
create function public.set_restaurant_storefront_content_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_version integer,p_expected_storefront_branch_id uuid,p_document jsonb)
returns jsonb language sql volatile security invoker set search_path='' as $$select app.set_restaurant_storefront_content_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_expected_version,p_expected_storefront_branch_id,p_document);$$;

create function app.invalidate_storefront_content_v1() returns trigger language plpgsql volatile security definer set search_path='' as $$
declare changed boolean:=false;
begin
 if convert_to(old.hero_headline,'UTF8') is distinct from convert_to(new.hero_headline,'UTF8') then
  update app.storefront_content_profiles set headline_format_text=null,headline_highlight_start=null,headline_highlight_end=null,headline_break_before=null
   where organization_id=new.organization_id and restaurant_id=new.restaurant_id and headline_format_text is not null;
  changed:=found;
  if changed then perform app.management_audit(new.organization_id,new.restaurant_id,new.storefront_branch_id,'settings.storefront.content.format_invalidated',null,jsonb_build_object('reason','headline_changed'));end if;
 end if;
 if old.storefront_branch_id is distinct from new.storefront_branch_id or (old.deleted_at is null and new.deleted_at is not null) then
  update app.storefront_content_profiles set deleted_at=coalesce(deleted_at,now()),headline_format_text=null,headline_highlight_start=null,headline_highlight_end=null,headline_break_before=null
   where organization_id=new.organization_id and restaurant_id=new.restaurant_id and (storefront_branch_id=old.storefront_branch_id or new.deleted_at is not null);
  update app.storefront_category_presentation set deleted_at=coalesce(deleted_at,now()) where organization_id=new.organization_id and restaurant_id=new.restaurant_id and (storefront_branch_id=old.storefront_branch_id or new.deleted_at is not null);
  update app.storefront_item_presentation set deleted_at=coalesce(deleted_at,now()) where organization_id=new.organization_id and restaurant_id=new.restaurant_id and (storefront_branch_id=old.storefront_branch_id or new.deleted_at is not null);
  update app.storefront_content_profiles set headline_format_text=null,headline_highlight_start=null,headline_highlight_end=null,headline_break_before=null where organization_id=new.organization_id and restaurant_id=new.restaurant_id and headline_format_text is not null;
  perform app.management_audit(new.organization_id,new.restaurant_id,new.storefront_branch_id,'settings.storefront.content.invalidated',null,jsonb_build_object('reason',case when new.deleted_at is not null then 'profile_deleted' else 'storefront_branch_changed' end));
 end if;
 return new;
end; $$;
create trigger storefront_content_legacy_invalidation after update of hero_headline,storefront_branch_id,deleted_at on public.restaurant_storefront_profiles for each row execute function app.invalidate_storefront_content_v1();

create function public.storefront_menu_v4(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;p public.restaurant_storefront_profiles%rowtype;v jsonb;d jsonb;content jsonb;promo jsonb;story jsonb;cats jsonb;h jsonb;
begin
 m:=public.storefront_menu_v3(p_slug);if m->>'ok' is distinct from 'true' then return m;end if;
 if m#>>'{restaurant,slug}' is distinct from p_slug then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');end if;
 select p0.* into p from public.restaurant_storefront_profiles p0
  join public.organizations o on o.id=p0.organization_id join public.restaurants r on r.id=p0.restaurant_id and r.organization_id=p0.organization_id
  join public.branches b on b.id=p0.storefront_branch_id and b.restaurant_id=p0.restaurant_id and b.organization_id=p0.organization_id
 where p0.slug=p_slug and p0.deleted_at is null and p0.is_published and o.status='active' and o.deleted_at is null and r.status='active' and r.deleted_at is null
  and b.status='active' and b.deleted_at is null and coalesce(b.timezone,r.timezone) is not null and coalesce(r.currency_override,o.default_currency)='ILS' and (not b.tax_enabled or b.tax_mode='exclusive');
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');end if;
 v:=app.storefront_content_read_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,p.hero_headline,p.hero_subline,p.announcement_text,m);d:=v->'document';h:=d->'hero';
 if h->>'mode'='editorial' then h:=jsonb_set(h,'{item_id}','null');end if;
 promo:=d->'promo';if promo<>'null'::jsonb then
  if promo#>>'{target,kind}'='category' then promo:=(promo-'target'-'editorial_media_id')||jsonb_build_object('kind','category','category_id',promo#>'{target,category_id}','image_url',app.storefront_content_media_url_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,(promo->>'editorial_media_id')::uuid));
  else promo:=(promo-'target')||jsonb_build_object('kind','item','item_id',promo#>'{target,item_id}');end if;
 end if;
 story:=d->'story';if story<>'null'::jsonb then story:=(story-'editorial_media_id')||jsonb_build_object('image_url',app.storefront_content_media_url_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,(story->>'editorial_media_id')::uuid));end if;
 select coalesce(jsonb_agg((x.v-'editorial_media_id')||jsonb_build_object('image_url',app.storefront_content_media_url_v1(p.organization_id,p.restaurant_id,p.storefront_branch_id,(x.v->>'editorial_media_id')::uuid)) order by x.n),'[]') into cats from jsonb_array_elements(d->'category_presentation') with ordinality x(v,n);
 content:=jsonb_build_object('schema',1,'hero',h,'announcement_segments',d->'announcement_segments','promo',promo,'story',story,'category_presentation',cats,'item_presentation',d->'item_presentation');
 return m||jsonb_build_object('content_v1',content);
end; $$;
-- CONTENT_MEDIA_COMPATIBILITY_INSERTION_POINT
create function app.storefront_content_lock_v1(p_org uuid,p_restaurant uuid)
returns void language plpgsql volatile set search_path='' as $$
begin
 -- Caller has already acquired restaurant -> profile, matching legacy paths.
 perform 1 from app.storefront_content_profiles c where c.organization_id=p_org and c.restaurant_id=p_restaurant order by c.storefront_branch_id for update;
 perform 1 from app.storefront_category_presentation c where c.organization_id=p_org and c.restaurant_id=p_restaurant order by c.storefront_branch_id,c.category_id for update;
 perform 1 from app.storefront_item_presentation i where i.organization_id=p_org and i.restaurant_id=p_restaurant order by i.storefront_branch_id,i.item_id for update;
 if app.actor_rank_in_scope(p_org,p_restaurant,null)<2 then raise exception 'storefront media authority changed' using errcode='42501';end if;
end; $$;
create function app.storefront_content_media_in_use_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_media uuid)
returns boolean language sql stable set search_path='' as $$
 select coalesce(exists(select 1 from app.storefront_content_profiles c where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null
   and (c.promo_media_id=p_media or c.story_media_id=p_media))
  or exists(select 1 from app.storefront_category_presentation c join app.storefront_content_profiles p using(organization_id,restaurant_id,storefront_branch_id)
   where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null and p.deleted_at is null and c.editorial_media_id=p_media),false);
$$;
create function app.storefront_content_repoint_media_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_old uuid,p_new uuid)
returns void language plpgsql volatile set search_path='' as $$
begin
 if not exists(select 1 from public.storefront_media a join public.storefront_media b on b.organization_id=a.organization_id and b.restaurant_id=a.restaurant_id and b.source_bucket=a.source_bucket and b.source_key=a.source_key and b.variant=a.variant
   where a.organization_id=p_org and a.restaurant_id=p_restaurant and a.id=p_old and b.id=p_new and b.published_at is not null and b.unpublished_at is null) then raise exception 'storefront content media replacement mismatch' using errcode='23514';end if;
 update app.storefront_content_profiles set promo_media_id=case when promo_media_id=p_old then p_new else promo_media_id end,story_media_id=case when story_media_id=p_old then p_new else story_media_id end
  where organization_id=p_org and restaurant_id=p_restaurant and storefront_branch_id=p_branch and deleted_at is null and (promo_media_id=p_old or story_media_id=p_old);
 update app.storefront_category_presentation c set editorial_media_id=p_new where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null and c.editorial_media_id=p_old
  and exists(select 1 from app.storefront_content_profiles p where p.organization_id=c.organization_id and p.restaurant_id=c.restaurant_id and p.storefront_branch_id=c.storefront_branch_id and p.deleted_at is null);
 perform app.management_audit(p_org,p_restaurant,p_branch,'settings.storefront.content.media_replaced',jsonb_build_object('media_id',p_old),jsonb_build_object('media_id',p_new));
end; $$;

create or replace function app.finalize_storefront_media(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_media_id          uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_rank         integer;
  v_fp           text;
  v_replay       jsonb;
  v_result       jsonb;
  v_snapshot jsonb;
  v_row          public.storefront_media%rowtype;
  v_old          public.storefront_media%rowtype;
  v_has_old      boolean;
  v_prof         public.restaurant_storefront_profiles%rowtype;
  v_has_prof     boolean;
  v_repoint      boolean := false;
  v_prof_version integer;
  v_meta         jsonb;
  v_size         text;
  v_republished  boolean;
  v_before       jsonb;
  v_after        jsonb;
  c_entity constant text := 'storefront_media';
begin
  if v_actor is null then
    raise exception 'finalize_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_media_id is null then
    raise exception 'finalize_storefront_media: client_request_id, organization_id, restaurant_id and media_id are required' using errcode = '42501';
  end if;
  -- the restaurant must belong to the organization BEFORE any authority branch: a foreign or
  -- unknown restaurant raises like rank 0 (no typed answer, no audit row under a foreign id)
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'finalize_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'finalize_storefront_media: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.media.denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'operation', 'finalize'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;

  -- lock order: restaurant -> profile -> media
  perform 1 from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'finalize_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  select * into v_prof from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null
   for update;
  v_has_prof := found;
  perform app.storefront_content_lock_v1(p_organization_id,p_restaurant_id);

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'media', p_media_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'finalize_storefront_media', v_fp);

  -- A REPLAY re-reads its row too (as the stage replay does): the stored answer is always a
  -- publication, so a row retracted since (or gone) makes that answer stale -- the caller must
  -- restart with a new request (which republishes RETRACTED -> LIVE), never be told "published".
  select * into v_row from public.storefront_media sm
   where sm.id = p_media_id and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', case when v_replay is null then 'not_found' else 'stale_request' end, 'entity', c_entity);
  end if;
  if v_replay is not null and (v_row.published_at is null or v_row.unpublished_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'stale_request', 'entity', c_entity);
  end if;

  -- Freshness applies to initial publication, already-LIVE publication and
  -- idempotent replay. A cached success is never authority for a stale item.
  if v_row.source_bucket = 'menu-images' and v_row.variant = 'w480' then
    v_snapshot := app.storefront_item_source_snapshot(p_organization_id, p_restaurant_id, v_row.source_key);
    if v_snapshot is null then
      return jsonb_build_object('ok', false, 'error', 'source_not_found', 'entity', c_entity);
    end if;
    if v_row.item_source_snapshot is distinct from v_snapshot then
      return jsonb_build_object('ok', false, 'error', 'source_stale', 'entity', c_entity);
    end if;
  end if;

  -- The point-in-time object check: a storage.objects ROW exists under the registered content
  -- address and its DECLARED metadata says image/webp and exactly the staged size. It runs for
  -- EVERY outcome, a replay and an already-LIVE row included (the object could have been removed
  -- through the raw Storage API by a manager of the restaurant: the registration-keyed policies
  -- of READ-001 allow it). It is NOT a proof of the bytes: the metadata is what the storage API
  -- recorded for the upload, and the bytes are never read here, so neither their format nor
  -- their hash is verified (the canonical recipe is the Edge Function's; see the header).
  select o.metadata into v_meta from storage.objects o
   where o.bucket_id = 'storefront-media' and o.name = v_row.object_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'object_missing', 'entity', c_entity);
  end if;
  v_size := v_meta ->> 'size';
  if coalesce(v_meta ->> 'mimetype', '') <> 'image/webp'
     or v_size is null or v_size !~ '^[0-9]{1,9}$' or v_size::integer <> v_row.bytes then
    return jsonb_build_object('ok', false, 'error', 'object_mismatch', 'entity', c_entity);
  end if;
  if v_replay is not null then
    return v_replay;
  end if;

  if v_row.published_at is not null and v_row.unpublished_at is null then
    v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
      'media_id', v_row.id, 'object_key', v_row.object_key, 'state', 'published',
      'already_published', true, 'republished', false, 'replaced_media_id', null, 'profile_version', null);
    v_replay := app.management_claim_request(v_actor, p_client_request_id, 'finalize_storefront_media', v_fp, v_result);
    return coalesce(v_replay, v_result);
  end if;

  v_republished := v_row.unpublished_at is not null;

  -- same-source replacement: the LIVE row of the same (source, variant), if any
  select * into v_old from public.storefront_media sm
   where sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
     and sm.source_bucket = v_row.source_bucket and sm.source_key = v_row.source_key and sm.variant = v_row.variant
     and sm.id <> v_row.id and sm.published_at is not null and sm.unpublished_at is null
   for update;
  v_has_old := found;
  if v_has_old and v_has_prof and (v_prof.logo_media_id = v_old.id or v_prof.hero_media_id = v_old.id) then
    v_repoint := true;
  end if;
  if v_has_old and v_has_prof and app.storefront_content_media_in_use_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_old.id) then
    v_repoint := true;
  end if;
  v_prof_version := case when v_repoint then v_prof.version + 1 else null end;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
    'media_id', v_row.id, 'object_key', v_row.object_key, 'state', 'published',
    'already_published', false, 'republished', v_republished,
    'replaced_media_id', case when v_has_old then v_old.id else null end,
    'profile_version', v_prof_version);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'finalize_storefront_media', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_has_old then
    -- retract the old row FIRST (the LIVE-only unique index admits one LIVE row per source)
    v_before := to_jsonb(v_old);
    update public.storefront_media
       set unpublished_at = greatest(now(), published_at)
     where id = v_old.id
     returning * into v_old;
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id,
                                     action, reason, old_values, new_values)
    values (p_organization_id, p_restaurant_id, null, v_actor, null,
            'settings.storefront.media.retracted', 'media_replaced', v_before, to_jsonb(v_old));
  end if;

  v_before := to_jsonb(v_row);
  update public.storefront_media
     set published_at = now(), unpublished_at = null
   where id = v_row.id
   returning * into v_row;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.published', v_before, to_jsonb(v_row));

  if v_repoint then
    if app.storefront_content_media_in_use_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_old.id) then
      perform app.storefront_content_repoint_media_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_old.id,v_row.id);
    end if;
    -- move every profile pointer from the replaced row to this one, atomically (no blank slot)
    v_before := to_jsonb(v_prof);
    update public.restaurant_storefront_profiles p
       set logo_media_id = case when p.logo_media_id = v_old.id then v_row.id else p.logo_media_id end,
           hero_media_id = case when p.hero_media_id = v_old.id then v_row.id else p.hero_media_id end,
           version       = v_prof_version
     where p.restaurant_id = p_restaurant_id
     returning to_jsonb(p.*) into v_after;
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id,
                                     action, reason, old_values, new_values)
    values (p_organization_id, p_restaurant_id, null, v_actor, null,
            'settings.storefront.updated', 'media_replaced', v_before, v_after);
  end if;
  return v_result;
end;
$$;

create or replace function app.retract_storefront_media(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_media_id          uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_fp       text;
  v_replay   jsonb;
  v_result   jsonb;
  v_row      public.storefront_media%rowtype;
  v_before   jsonb;
  v_prof     public.restaurant_storefront_profiles%rowtype;
  v_has_prof boolean;
  v_slots    text[] := '{}';
  c_entity constant text := 'storefront_media';
begin
  if v_actor is null then
    raise exception 'retract_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_media_id is null then
    raise exception 'retract_storefront_media: client_request_id, organization_id, restaurant_id and media_id are required' using errcode = '42501';
  end if;
  -- the restaurant must belong to the organization BEFORE any authority branch: a foreign or
  -- unknown restaurant raises like rank 0 (no typed answer, no audit row under a foreign id)
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'retract_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'retract_storefront_media: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.media.denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'operation', 'retract'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;
  perform 1 from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'retract_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  select * into v_prof from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null
   for update;
  v_has_prof := found;
  perform app.storefront_content_lock_v1(p_organization_id,p_restaurant_id);

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'media', p_media_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'retract_storefront_media', v_fp);

  -- A REPLAY re-reads its row too (as the stage and finalize replays do): the stored answer is
  -- always "retracted", so a row gone since, or LIVE again since (RETRACTED -> LIVE through a
  -- later finalize), makes that answer stale -- the caller must look again (list) or retract
  -- with a new request, never be told "retracted" for a publicly referenceable row. Not claimed.
  select * into v_row from public.storefront_media sm
   where sm.id = p_media_id and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', case when v_replay is null then 'not_found' else 'stale_request' end, 'entity', c_entity);
  end if;
  if v_replay is not null then
    if v_row.published_at is not null and v_row.unpublished_at is not null then
      return v_replay;   -- still RETRACTED: the stored answer holds
    end if;
    return jsonb_build_object('ok', false, 'error', 'stale_request', 'entity', c_entity);
  end if;
  if v_row.published_at is null then
    return jsonb_build_object('ok', false, 'error', 'media_not_published', 'entity', c_entity);
  end if;
  if v_row.unpublished_at is not null then
    v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
      'media_id', v_row.id, 'state', 'retracted', 'already_retracted', true);
    v_replay := app.management_claim_request(v_actor, p_client_request_id, 'retract_storefront_media', v_fp, v_result);
    return coalesce(v_replay, v_result);
  end if;
  if v_has_prof then
    if v_prof.logo_media_id = v_row.id then v_slots := v_slots || 'logo'::text; end if;
    if v_prof.hero_media_id = v_row.id then v_slots := v_slots || 'hero'::text; end if;
  end if;
  if coalesce(array_length(v_slots, 1), 0) > 0 or (v_has_prof and app.storefront_content_media_in_use_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_row.id)) then
    return jsonb_build_object('ok', false, 'error', 'media_in_use', 'slots', to_jsonb(v_slots), 'entity', c_entity);
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
    'media_id', v_row.id, 'state', 'retracted', 'already_retracted', false);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'retract_storefront_media', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;
  v_before := to_jsonb(v_row);
  update public.storefront_media
     set unpublished_at = greatest(now(), published_at)
   where id = v_row.id
   returning * into v_row;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.retracted', v_before, to_jsonb(v_row));
  return v_result;
end;
$$;

create function app.list_storefront_content_media_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.restaurant_storefront_profiles%rowtype;media jsonb;
begin
 if app.current_app_user_id() is null then raise exception 'storefront media authentication required' using errcode='42501';end if;
 if p_organization_id is null or p_restaurant_id is null or not exists(select 1 from public.restaurants r where r.organization_id=p_organization_id and r.id=p_restaurant_id and r.deleted_at is null)
  or app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null)<2 then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_content_media');end if;
 select * into p from public.restaurant_storefront_profiles where organization_id=p_organization_id and restaurant_id=p_restaurant_id and deleted_at is null;
 if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_content_media');end if;
 select coalesce(jsonb_agg(j order by created_at desc,id),'[]') into media from (
  select m.id,m.created_at,jsonb_build_object('id',m.id,'source_bucket',m.source_bucket,'source_key',m.source_key,'variant',m.variant,'object_key',m.object_key,'content_hash',m.content_hash,
   'width',m.width,'height',m.height,'bytes',m.bytes,'state',case when m.published_at is null then 'staged' when m.unpublished_at is null then 'published' else 'retracted' end,
   'published_at',m.published_at,'unpublished_at',m.unpublished_at,'created_at',m.created_at,
   'in_use',to_jsonb(array_remove(array[case when m.id=p.logo_media_id then 'logo' end,case when m.id=p.hero_media_id then 'hero' end],null)),
   'content_in_use',coalesce((select jsonb_agg(usage order by usage->>'kind',usage->>'category_id') from (
    select jsonb_build_object('kind','promo') usage from app.storefront_content_profiles c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id and c.storefront_branch_id=p.storefront_branch_id and c.deleted_at is null and c.promo_media_id=m.id
    union all select jsonb_build_object('kind','story') from app.storefront_content_profiles c where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id and c.storefront_branch_id=p.storefront_branch_id and c.deleted_at is null and c.story_media_id=m.id
    union all select jsonb_build_object('kind','category','category_id',c.category_id) from app.storefront_category_presentation c join app.storefront_content_profiles cp using(organization_id,restaurant_id,storefront_branch_id)
     where c.organization_id=p_organization_id and c.restaurant_id=p_restaurant_id and c.storefront_branch_id=p.storefront_branch_id and c.deleted_at is null and cp.deleted_at is null and c.editorial_media_id=m.id) usages),'[]'::jsonb)) j
  from public.storefront_media m where m.organization_id=p_organization_id and m.restaurant_id=p_restaurant_id and m.variant='w960'
   and ((m.source_bucket='restaurant-logos' and exists(select 1 from app.restaurant_logo_scope(m.source_key) s where s.organization_id=p_organization_id and s.restaurant_id=p_restaurant_id))
     or (m.source_bucket='menu-images' and exists(select 1 from app.menu_image_scope(m.source_key) s where s.organization_id=p_organization_id and s.restaurant_id=p_restaurant_id and (s.branch_id is null or s.branch_id=p.storefront_branch_id))))
  order by m.created_at desc,m.id limit 200) rows;
 return jsonb_build_object('ok',true,'entity','storefront_content_media','restaurant_id',p_restaurant_id,'version',p.version,'media_prefix',app.storefront_media_prefix(p_restaurant_id),'media',media);
end; $$;
create function public.list_storefront_content_media_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$select app.list_storefront_content_media_v1(p_organization_id,p_restaurant_id);$$;

-- CONTENT_GRANTS_INSERTION_POINT
do $$ declare r record;begin
 for r in select p.oid::regprocedure identity from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='app' and (p.proname like 'storefront_content_%' or p.proname in ('get_restaurant_storefront_content_v1','set_restaurant_storefront_content_v1','invalidate_storefront_content_v1','list_storefront_content_media_v1')) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',r.identity);
 end loop;
end; $$;
revoke all on function public.get_restaurant_storefront_content_v1(uuid,uuid),public.set_restaurant_storefront_content_v1(uuid,uuid,uuid,integer,uuid,jsonb),public.list_storefront_content_media_v1(uuid,uuid),public.storefront_menu_v4(text) from public,anon,authenticated,service_role;
grant execute on function app.get_restaurant_storefront_content_v1(uuid,uuid),public.get_restaurant_storefront_content_v1(uuid,uuid),app.set_restaurant_storefront_content_v1(uuid,uuid,uuid,integer,uuid,jsonb),public.set_restaurant_storefront_content_v1(uuid,uuid,uuid,integer,uuid,jsonb),app.list_storefront_content_media_v1(uuid,uuid),public.list_storefront_content_media_v1(uuid,uuid) to authenticated;
grant execute on function public.storefront_menu_v4(text) to anon,service_role;
comment on function public.storefront_menu_v4(text) is 'BIZBOT-STOREFRONT-CONTENT-CONTRACT-001: single v3 call and same-snapshot server-normalized bounded presentation only. No order, pricing, device or print authority.';
commit;
