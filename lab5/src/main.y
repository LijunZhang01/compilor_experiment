%{
	#include "common.h"
	#define YYSTYPE TreeNode *

	TreeNode* root = new TreeNode(0, NODE_PROG);
	extern int lineno;

	// max_scope_id 是堆栈下一层结点的最大编号
	unsigned char max_scope_id = SCOPT_ID_BASE;
	string presentScope = "" + SCOPT_ID_BASE;
	unsigned int top = 0;

	// multimap <标识符名称， 作用域> 变量名列表
	multimap<string, string> idNameList = {
		{"scanf", "0"},
		{"printf", "0"}
	};
	// map <<标识符名称， 作用域>, 结点指针> 变量列表
	map<pair<string, string>, TreeNode*> idList = {
		{make_pair("scanf", "0"), nodeScanf},
		{make_pair("printf", "0"), nodePrintf}
	};

	int yylex();
	int yyerror( char const * );
	int scopeCmp(string preScope, string varScope);
	void scopePush();
	void scopePop();
%}

// 类型
%token T_CHAR T_INT T_STRING T_BOOL T_VOID

// 取地址运算符
%token ADDR;

// 赋值运算符
%token ASSIGN PLUSASSIGN MINUSASSIGN MULASSIGN DIVASSIGN

// 括号分号逗号
%token SEMICOLON COMMA LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET

// 关键字
%token CONST IF ELSE WHILE FOR BREAK CONTINUE RETURN

// 比较运算符
%token EQ GRAEQ LESEQ NEQ  GRA LES

// 普通计算
%token PLUS MINUS MUL DIV MOD AND OR NOT

// 特殊单词
%token IDENTIFIER INTEGER CHAR BOOL STRING

%left EQ

%%

program
: decl {root->addChild($1);}
| funcDef {root->addChild($1);}
| program decl {root->addChild($2);}
| program funcDef {root->addChild($2);}
;

// ---------------- 类型与复合标识符 -------------------

basicType
: T_INT {$$ = new TreeNode(lineno, NODE_TYPE); $$->type = TYPE_INT;}
| T_CHAR {$$ = new TreeNode(lineno, NODE_TYPE); $$->type = TYPE_CHAR;}
| T_BOOL {$$ = new TreeNode(lineno, NODE_TYPE); $$->type = TYPE_BOOL;}
| T_VOID {$$ = new TreeNode(lineno, NODE_TYPE); $$->type = TYPE_VOID;}
;

// ------ 复合标识符，包含指针与数组，在变量声明外使用 -----
compIdentifier
: pIdentifier {$$ = $1;}
| arrayIdentifier {$$ = $1;}
;

// 指针标识符
pIdentifier
: identifier {$$ = new TreeNode($1);}
| MUL pIdentifier {$$ = $1; $$->pointLevel++;}
| ADDR pIdentifier {$$ = $1; $$->pointLevel--;}
;

// 数组标识符
arrayIdentifier
: pIdentifier LBRACKET expr RBRACKET {}
| arrayIdentifier LBRACKET expr RBRACKET {}
;

identifier
: IDENTIFIER {
	$$ = $1;
	int idNameCount = idNameList.count($$->var_name);
	int declCnt = 0;
	int minDefDis = MAX_SCOPE_STACK;

	// 搜索变量是否已经声明
	auto it = idNameList.find($$->var_name);
	while (idNameCount--) {
		int resScoptCmp = scopeCmp(presentScope, it->second);
		if (resScoptCmp >= 0){
			// 寻找最近的定义
			if (resScoptCmp < minDefDis) {
				minDefDis = resScoptCmp;
				$$ = idList[make_pair(it->first, it->second)];
			}
			declCnt++;
		}
		it++;
	}
	if (declCnt == 0) {
		string t = "Undeclared identifier :\"" + $1->var_name + "\", scope : " + presentScope;
		yyerror(t.c_str());
	}
};

// --------- 声明用标识符 ----------
declCompIdentifier
: pDeclIdentifier {$$ = $1;}
| constArrayIdentifier {$$ = $1;}
;

pDeclIdentifier
: declIdentifier {$$ = new TreeNode($1);}
| MUL pIdentifier {$$ = $1; $$->pointLevel++;}
| ADDR pIdentifier {$$ = $1; $$->pointLevel--;}
;

// 常量数组标识符（仅供声明使用）
constArrayIdentifier
: pIdentifier LBRACKET INTEGER RBRACKET {
  $$ = $1;
  $$->type = new Type(VALUE_ARRAY);
  $$->type->elementType = $1->type->type;
  $$->type->dimSize[$$->type->dim] = $3->int_val;
  $$->type->dim++;
}
| constArrayIdentifier LBRACKET INTEGER RBRACKET {
  $$ = $1;
  $$->type->dimSize[$$->type->dim] = $3->int_val;
  $$->type->dim++;
}
;

declIdentifier
: IDENTIFIER {
	$$ = $1;
	$$->var_scope = presentScope;
	if (idList.count(make_pair($1->var_name, $1->var_scope)) != 0) {
		string t = "Redeclared identifier : " + $1->var_name;
		yyerror(t.c_str());
	}
	idNameList.insert(make_pair($1->var_name, $1->var_scope));
	idList[make_pair($1->var_name, $1->var_scope)] = $1;
}
;

// ---------------- 常变量声明 -------------------

decl
: constDecl {$$ = $1;}
| varDecl {$$ = $1;}
;

constDecl
: CONST basicType constDefs SEMICOLON {
  $$ = new TreeNode(lineno, NODE_STMT);
  $$->stype = STMT_CONSTDECL;
  $$->type = $2->type;
  $$->addChild($2);
  $$->addChild($3);
};

// 连续常量定义
constDefs
: constDef {$$ = $1;}
| constDefs COMMA constDef {$$ = $1; $$->addSibling($3);}
;

constDef
: pDeclIdentifier ASSIGN INTEGER {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_ASSIGN; $$->addChild($1); $$->addChild($3);}
| constArrayIdentifier ASSIGN LBRACE ArrayInitVal RBRACE {}
;

// 数组初始化值
ArrayInitVal
: INTEGER {$$ = $1;}
| ArrayInitVal COMMA INTEGER {$$ = $1; $$->addSibling($3);}
;

varDecl
: basicType varDefs SEMICOLON {
  $$ = new TreeNode(lineno, NODE_STMT);
  $$->stype = STMT_DECL;
  $$->type = $1->type;
  $$->addChild($1);
  $$->addChild($2);
}
;

// 连续变量定义
varDefs
: varDef {$$ = $1;}
| varDefs COMMA varDef {$$ = $1; $$->addSibling($2);}
;

varDef
: declCompIdentifier {}
| declCompIdentifier ASSIGN expr {}
| constArrayIdentifier ASSIGN LBRACE ArrayInitVal RBRACE {}
;

// ---------------- 函数声明 -------------------

funcDef
: basicType pDeclIdentifier LPAREN funcFParams RPAREN block {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_DECL;
	$$->addChild($1);
	$$->addChild($2);
	TreeNode* params = new TreeNode(lineno, NODE_PARAM);
	params->addChild($4);
	$$->addChild(params);
	$$->addChild($6);
	scopePop();
}
| basicType pDeclIdentifier LPAREN RPAREN block {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_DECL;
	$$->addChild($1);
	$$->addChild($2);
	$$->addChild(new TreeNode(lineno, NODE_PARAM));
	$$->addChild($5);
	scopePop();
}
;

funcFParams
: funcFParam {$$ = $1;}
| funcFParams COMMA funcFParam {$$ = $1; $$->addSibling($3);}
;

funcFParam
: basicType pDeclIdentifier {$$ = new TreeNode(lineno, NODE_PARAM); $$->addChild($1); $$->addChild($2);}
;

// ---------------- 语句块 -------------------

block
: LBRACE blockItems RBRACE {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_BLOCK;
	$$->addChild($2);
	scopePop();
};

blockItems
: blockItem {$$ = $1;}
| blockItems blockItem {$$ = $1; $$->addSibling($2);}
;

blockItem
: decl {$$ = $1;}
| stmt {$$ = $1;}
;

stmt
: SEMICOLON {$$ = new TreeNode(lineno, NODE_STMT); $$->stype = STMT_SKIP;}
| block {$$ = $1;}
| expr {$$ = $1;}
| compIdentifier ASSIGN expr SEMICOLON {
	$$ = new TreeNode(lineno, NODE_OP);
	$$->optype = OP_ASSIGN;
	$$->addChild($1);
	$$->addChild($3);
}

| IF LPAREN cond RPAREN stmt ELSE stmt {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_IFELSE;
	$$->addChild($3);
	$$->addChild($5);
	$$->addChild($7);
	scopePop();
}
| IF LPAREN cond RPAREN stmt {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_IF;
	$$->addChild($3);
	$$->addChild($5);
	scopePop();
}
| WHILE LPAREN cond RPAREN stmt {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_WHILE;
	$$->addChild($3);
	$$->addChild($5);
	scopePop();
}
| FOR LPAREN expr SEMICOLON cond SEMICOLON expr RPAREN stmt {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_FOR;
	$$->addChild($3);
	$$->addChild($5);
	$$->addChild($7);
	$$->addChild($9);
	scopePop();
}

| BREAK SEMICOLON {$$ = new TreeNode(lineno, NODE_STMT); $$->stype = STMT_BREAK;}
| CONTINUE SEMICOLON{$$ = new TreeNode(lineno, NODE_STMT); $$->stype = STMT_CONTINUE;}
| RETURN SEMICOLON {$$ = new TreeNode(lineno, NODE_STMT); $$->stype = STMT_RETURN;}
| RETURN expr SEMICOLON {$$ = new TreeNode(lineno, NODE_STMT); $$->stype = STMT_RETURN; $$->addChild($2);}
;


// ---------------- 表达式 -------------------

expr
: andExpr {$$ = new TreeNode(lineno, NODE_EXPR); $$->addChild($1);}
;

cond
: LOrExpr {$$ = new TreeNode(lineno, NODE_EXPR); $$->addChild($1);}
;

andExpr
: mulExpr {$$ = $1;}
| andExpr PLUS mulExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_ADD; $$->addChild($1); $$->addChild($3);}
| andExpr MINUS mulExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_SUB; $$->addChild($1); $$->addChild($3);}
;

// factor
mulExpr
: unaryExpr {$$ = $1;}
| mulExpr MUL unaryExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_MUL; $$->addChild($1); $$->addChild($3);}
| mulExpr DIV unaryExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_DIV; $$->addChild($1); $$->addChild($3);}
| mulExpr MOD unaryExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_MOD; $$->addChild($1); $$->addChild($3);}
;

// 一元表达式
unaryExpr
: primaryExpr {$$ = $1;}
| pIdentifier LPAREN funcRParams RPAREN {
	scopePush();
	$$ = new TreeNode(lineno, NODE_STMT);
	$$->stype = STMT_FUNCALL;
	$$->addChild($3);
	scopePop();
}
| PLUS unaryExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_POS; $$->addChild($2);}
| MINUS unaryExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_NAG; $$->addChild($2);}
| NOT unaryExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_NOT; $$->addChild($2);}
;

// 基本表达式
primaryExpr
: LPAREN expr RPAREN {$$ = $2;}
| arrayIdentifier {$$ = $1;}
| INTEGER {$$ = $1;}
;

// 函数调用
funcRParams
: expr {$$ = $1;}
| funcRParams COMMA expr {$$ = $1; $$->addSibling($3);}
;

// 或表达式
LOrExpr
: LAndExpr {$$ = $1;}
| LOrExpr OR LAndExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_OR; $$->addChild($1); $$->addChild($3);}
;

// 与
LAndExpr
: eqExpr {$$ = $1;}
| LAndExpr AND eqExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_AND; $$->addChild($1); $$->addChild($3);}
;

// 相等关系
eqExpr
: relExpr {$$ = $1;}
| eqExpr EQ relExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_EQ; $$->addChild($1); $$->addChild($3);}
| eqExpr NEQ relExpr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_NEQ; $$->addChild($1); $$->addChild($3);}
;

// 相对关系
relExpr
: expr {$$ = $1;}
| relExpr GRA expr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_GRA; $$->addChild($1); $$->addChild($3);}
| relExpr LES expr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_LES; $$->addChild($1); $$->addChild($3);}
| relExpr GRAEQ expr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_GRAEQ; $$->addChild($1); $$->addChild($3);}
| relExpr LESEQ expr {$$ = new TreeNode(lineno, NODE_OP); $$->optype = OP_LESEQ; $$->addChild($1); $$->addChild($3);}
;

%%

/*
 *  输入参数： 
 *    presScope： 当前变量所处的作用域
 *    varScope:   希望进行比较的已声明变量作用域
 *
 *  返回值：
 *    0： 作用域相同，
 *          若为变量声明语句，为变量重定义。
 *   >0： 已声明变量作用域在当前作用域外层，返回作用域距离（堆栈层数）
 *          若为声明语句，不产生冲突，当前变量为新定义变量，
 *          若为使用语句，当前变量为新定义变量。
 *   -1：已声明变量作用域在当前作用域内层，
 *          若为声明语句，不可能出现这种情况，
 *          若为使用语句，不产生冲突。
 *   -2：两个作用域互不包含，任何情况下都不会互相干扰
 */
int scopeCmp(string presScope, string varScope) {
	unsigned int plen = presScope.length(), vlen = varScope.length();
	unsigned int minlen = min(plen, vlen);
	if (presScope.substr(0, minlen) == varScope.substr(0, minlen)) {
		if (plen >= vlen)
			return plen - vlen;
		else
			return -1;
	}
	return -2;
}

void scopePush() {
	top++;
	// presentScope[top] = max_scope_id;
	presentScope += max_scope_id;
	max_scope_id = SCOPT_ID_BASE;
}

void scopePop() {
	max_scope_id = presentScope[top] + 1;
	presentScope = presentScope.substr(0, presentScope.length() - 1);
	top--;
}

int yyerror(char const * message)
{
	cout << "error: " << message << ", at line " << lineno << endl;
	return -1;
}
