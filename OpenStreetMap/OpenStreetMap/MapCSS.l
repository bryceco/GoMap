%{
#include "MapCssLex.h"
%}

%option prefix="MapCSS_"
%option noyywrap

%s IN_COMMENT

%%

[ \t]*						{ }

<INITIAL>{
"/*"					{ BEGIN(IN_COMMENT); }
\*						{ return MAPCSS_IDENT; }
[a-zA-Z][-a-zA-Z0-9_]*	{ return MAPCSS_IDENT; }
"-"?[0-9]+\.[0-9]+		{ return MAPCSS_FLOAT; }
"-"?[0-9]+				{ return MAPCSS_FLOAT; }
\"[^"]*\"				{ return MAPCSS_QUOTE; }
\#[0-9a-f]+				{ return MAPCSS_COLOR; }
">"						{ return MAPCSS_COMPARISON; }
">="					{ return MAPCSS_COMPARISON; }
"="						{ return MAPCSS_COMPARISON; }
"!="					{ return MAPCSS_COMPARISON; }
"=~"					{ return MAPCSS_COMPARISON; }
"<"						{ return MAPCSS_COMPARISON; }
"<="					{ return MAPCSS_COMPARISON; }
.						{ return yytext[0]; }
\n						yylineno++;
}

<IN_COMMENT>{
"*/"					{ BEGIN(INITIAL); }
[^*\n]+					// eat comment in chunks
"*"						// eat the lone star
\n						yylineno++;
}

%%
