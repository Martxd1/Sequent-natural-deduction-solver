%{
/*****************************************************
*
* atomos.l : El programa verifica la sintaxis, transforma la fórmula proporcionada a CNF y luego evalúa su satisfacibilidad
*
* Programmer: Martín Gómez Jímenéz
*	      Cristóbal Schmelzer Salinas
*
* Santiago de Chile, 25/5/2025
*
****************************************************/

// =======================================
// Definiciones y estructuras necesarias
// =======================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Tokens con valores enteros que representan operadores y paréntesis
#define TOKEN_NOT     1
#define TOKEN_AND     2
#define TOKEN_OR      3
#define TOKEN_IMPL    4
#define TOKEN_LPAREN  5
#define TOKEN_RPAREN  6
#define TOKEN_ATOM    7

//Variables de tokens
#define MAX_TOKENS 1000
int token_buffer[MAX_TOKENS];  
int current_token;
int token_count = 0;	       
int token_index = 0;

// Variables de control global
int opened = 0;              
int total_atomos = 0;        

// Variables de átomos 
struct Atomo {
    char nombre;         
    int valor;            
};
#define MAX_ATOMOS 100
int indice_atomico[MAX_TOKENS];
struct Atomo atomos[MAX_ATOMOS];

// Nodo de árbol de sintaxis abstracta (AST)
struct Node {
    int tipo;               
    struct Node *izq;       
    struct Node *der;        
    int indice_atomo;        
};

// =======================================
// Funciones auxiliares
// =======================================


// Crea un nuevo nodo del árbol (AST)
struct Node* crear_nodo(int tipo, struct Node* izq, struct Node* der, int indice_atomo) {
    struct Node* nuevo = calloc(1, sizeof(struct Node));
    
    nuevo->tipo = tipo;
    nuevo->izq = izq;
    nuevo->der = der;
    nuevo->indice_atomo = indice_atomo;
    
    return nuevo;
}

// Devuelve el siguiente token de token_buffer
int siguiente_token() {
    int token;
    if (token_index < token_count){
    	token = token_buffer[token_index];
    	token_index = token_index + 1;
    	return token;
    }
    return 0;
}

// Solicita el siguiente token de token_buffer
void advance() {
    current_token = siguiente_token();
}

// Verifica si un átomo ya existe en el arreglo
int existeAtomo(char nombre) {
    for (int i = 0; i < total_atomos; i = i + 1)
        if (atomos[i].nombre == nombre)
            return 1;
    return 0;
}

// Agrega un átomo único si no está repetido
void agregarAtomoUnico(char nombre) {
    if (total_atomos >= MAX_ATOMOS) {
        printf("Error: Se excedió el número máximo de átomos permitidos (%d)\n", MAX_ATOMOS);
        exit(1);
    }
    if (!existeAtomo(nombre)) {
        atomos[total_atomos].nombre = nombre;
        total_atomos = total_atomos + 1;
    }
    	
}

// Verifica si la lectura está dentro de los delimitadores $$
int verificar_dentro() {
    if (opened != 1) {
        printf("Error: Expresión fuera de delimitadores $...\n");
        exit(1);
    }
    return 1;
}

// =======================================
// Parsers descendentes para cada nivel de precedencia
// =======================================

struct Node* parse_formula();  // Entrada principal del parser
struct Node* parse_impl();     // Nivel de menor prioridad: Parser para la implicación (->)
struct Node* parse_or();       // Siguiente nivel de prioridad: Parser para la Disyunción (||)
struct Node* parse_and();      // Siguiente nivel de prioridad: Parser para la Conjunción (&&)
struct Node* parse_not();      // Siguiente nivel de prioridad: Parser para la Negación (¬)
struct Node* parse_atom();     // Siguiente nivel de prioridad: Parser para los Átomos o subfórmulas entre paréntesis

struct Node* parse_formula() {
    token_index = 0; 
    advance();        
    return parse_impl();
}

struct Node* parse_impl() {
    struct Node* izquierda = parse_or();
    if (current_token == TOKEN_IMPL) {
        advance();
        struct Node* derecha = parse_impl();
        return crear_nodo(TOKEN_IMPL, izquierda, derecha, -1);
    }
    return izquierda;
}

struct Node* parse_or() {
    struct Node* izquierda = parse_and();
    while (current_token == TOKEN_OR) {
        advance();
        struct Node* derecha = parse_and();
        izquierda = crear_nodo(TOKEN_OR, izquierda, derecha, -1);
    }
    return izquierda;
}

struct Node* parse_and() {
    struct Node* izquierda = parse_not();
    while (current_token == TOKEN_AND) {
        advance();
        struct Node* derecha = parse_not();
        izquierda = crear_nodo(TOKEN_AND, izquierda, derecha, -1);
    }
    return izquierda;
}

struct Node* parse_not() {
    if (current_token == TOKEN_NOT) {
        advance();
        struct Node* atom = parse_not();
        return crear_nodo(TOKEN_NOT, atom, NULL, -1);
    }
    return parse_atom();
}

struct Node* parse_atom() {
     if (current_token == TOKEN_LPAREN) {
        advance();
        struct Node* nodo = parse_impl();
        advance();
        return nodo;
    }
    if (current_token == TOKEN_ATOM) {
        int indice = indice_atomico[token_index - 1]; // Ya tienes el índice    
        struct Node* nodo = crear_nodo(TOKEN_ATOM, NULL, NULL, indice);
        advance();
        return nodo;
    }
    printf("Error: se esperaba átomo o '('\n");
    exit(1);
}


// Elimina las implicaciones del árbol del modo (A -> B) y las reemplaza por: (¬A) ∨ B
struct Node* implfree(struct Node* root) {
    if (root == NULL) return NULL;

    // Si es un átomo, simplemente devuelve el nodo
    if (root->tipo == TOKEN_ATOM) {
        return crear_nodo(TOKEN_ATOM, NULL, NULL, root->indice_atomo);
    }
    // Si es una negación, procesa recursivamente el hijo izquierdo
    else if (root->tipo == TOKEN_NOT) {
        struct Node* hijo = implfree(root->izq);
        return crear_nodo(TOKEN_NOT, hijo, NULL, -1);
    }
    // Si es una conjunción, procesa recursivamente ambos hijos
    else if (root->tipo == TOKEN_AND) {
        struct Node* izq2 = implfree(root->izq);
        struct Node* der2 = implfree(root->der);
        return crear_nodo(TOKEN_AND, izq2, der2, -1);
    }
    // Si es una disyunción, procesa recursivamente ambos hijos
    else if (root->tipo == TOKEN_OR) {
        struct Node* izq2 = implfree(root->izq);
        struct Node* der2 = implfree(root->der);
        return crear_nodo(TOKEN_OR, izq2, der2, -1);
    }
    // Si es una implicación, la reemplaza por (¬A) ∨ B
    else if (root->tipo == TOKEN_IMPL) {
        struct Node* A = implfree(root->izq);
        struct Node* B = implfree(root->der);
        struct Node* notA = crear_nodo(TOKEN_NOT, A, NULL, -1);
        return crear_nodo(TOKEN_OR, notA, B, -1);
    }

    return NULL;
}

// Convierte el árbol a su forma normal negativa (NNF(IMPL_FREE)) 
struct Node* nnf(struct Node* root) {
    if (root == NULL) return NULL;

    // Si es un átomo, simplemente devuelve el nodo
    if (root->tipo == TOKEN_ATOM) {
        return crear_nodo(TOKEN_ATOM, NULL, NULL, root->indice_atomo);
    }
    // Caso negación
    else if (root->tipo == TOKEN_NOT) {
        struct Node* hijo = root->izq;
        // Doble negación: ¬(¬A) = A
        if (hijo->tipo == TOKEN_NOT) {
            return nnf(hijo->izq);
        }
        // Leyes de Morgan: ¬(A ∧ B) = ¬A ∨ ¬B
        else if (hijo->tipo == TOKEN_AND) {
            struct Node* izq = nnf(crear_nodo(TOKEN_NOT, hijo->izq, NULL, -1));
            struct Node* der = nnf(crear_nodo(TOKEN_NOT, hijo->der, NULL, -1));
            return crear_nodo(TOKEN_OR, izq, der, -1);
        }
        // Leyes de Morgan: ¬(A ∨ B) = ¬A ∧ ¬B
        else if (hijo->tipo == TOKEN_OR) {
            struct Node* izq = nnf(crear_nodo(TOKEN_NOT, hijo->izq, NULL, -1));
            struct Node* der = nnf(crear_nodo(TOKEN_NOT, hijo->der, NULL, -1));
            return crear_nodo(TOKEN_AND, izq, der, -1);
        }
        // Si es un átomo: negación de átomo
        else if (hijo->tipo == TOKEN_ATOM) {
            return crear_nodo(TOKEN_NOT, crear_nodo(TOKEN_ATOM, NULL, NULL, hijo->indice_atomo), NULL, -1);
        }
        // Otro caso 
        else {
            return NULL;
        }
    }
    // Caso conjunción
    else if (root->tipo == TOKEN_AND) {
        struct Node* izq = nnf(root->izq);
        struct Node* der = nnf(root->der);
        return crear_nodo(TOKEN_AND, izq, der, -1);
    }
    // Caso disyunción
    else if (root->tipo == TOKEN_OR) {
        struct Node* izq = nnf(root->izq);
        struct Node* der = nnf(root->der);
        return crear_nodo(TOKEN_OR, izq, der, -1);
    }
    // Caso desconocido
    return NULL;
}

// Convierte la fórmula de NNF en CNF (conjunción de disyunciones).
struct Node* cnf(struct Node* root) {
    if (root == NULL) return NULL;

    // Aplicar recursión en hijos primero
    struct Node* A = cnf(root->izq);
    struct Node* B = cnf(root->der);

    // Caso átomo: simplemente clona el nodo átomo
    if (root->tipo == TOKEN_ATOM) {
        return crear_nodo(TOKEN_ATOM, NULL, NULL, root->indice_atomo);
    }
    // Caso negación: clona NOT y su hijo (el átomo)
    else if (root->tipo == TOKEN_NOT) {
        struct Node* hijo = NULL;
        if (root->izq != NULL) {
            hijo = cnf(root->izq);
        }
        return crear_nodo(TOKEN_NOT, hijo, NULL, -1);
    }
    else if (root->tipo == TOKEN_AND) {
        return crear_nodo(TOKEN_AND, A, B, -1);
    }
    else if (root->tipo == TOKEN_OR) {
        if (A != NULL && A->tipo == TOKEN_AND) {
            // (A1 ∧ A2) ∨ B => (A1∨B) ∧ (A2∨B)
            struct Node* A1 = A->izq;
            struct Node* A2 = A->der;
            struct Node* leftOr  = cnf(crear_nodo(TOKEN_OR, A1, B, -1));
            struct Node* rightOr = cnf(crear_nodo(TOKEN_OR, A2, B, -1));
            return crear_nodo(TOKEN_AND, leftOr, rightOr, -1);
        }
        else if (B != NULL && B->tipo == TOKEN_AND) {
            // A ∨ (B1 ∧ B2) => (A∨B1) ∧ (A∨B2)
            struct Node* B1 = B->izq;
            struct Node* B2 = B->der;
            struct Node* leftOr  = cnf(crear_nodo(TOKEN_OR, A, B1, -1));
            struct Node* rightOr = cnf(crear_nodo(TOKEN_OR, A, B2, -1));
            return crear_nodo(TOKEN_AND, leftOr, rightOr, -1);
        }
        else {
            return crear_nodo(TOKEN_OR, A, B, -1);
        }
    }
    else {
        return NULL;
    }
}

// =======================================
// Evaluación recursiva del árbol AST
// =======================================
// Recorre el árbol y evalúa la fórmula según los valores actuales de los átomos

// Retorna 1 si la fórmula es verdadera o 0 si es falsa bajo la asignación actual
int evaluar(struct Node* nodo) {
    if (nodo == NULL) return 0;

    if (nodo->tipo == TOKEN_ATOM) {
        return atomos[nodo->indice_atomo].valor;
    }
     
    int izq = evaluar(nodo->izq);
    int der = evaluar(nodo->der);

    // Operadores evaluados con if-else
    if (nodo->tipo == TOKEN_NOT) {
        return !izq;
    } else if (nodo->tipo == TOKEN_AND) {
        return izq && der;
    } else if (nodo->tipo == TOKEN_OR) {
        return izq || der;
    } else if (nodo->tipo == TOKEN_IMPL) {
        return (!izq || der);
    }
    
    return 0;
}

// Retorna 1 si encuentra una negación aplicada a AND u OR, 0 si todo está correcto
int tiene_negacion_sobre_operador(struct Node* nodo) {
    if (nodo == NULL) return 0;

    // Si el nodo actual es una negación sobre AND u OR
    if (nodo->tipo == TOKEN_NOT && nodo->izq != NULL) {
        int t = nodo->izq->tipo;
        if (t == TOKEN_AND || t == TOKEN_OR) {
            return 1;
        }
    }

    // Verificar recursivamente hijos
    return tiene_negacion_sobre_operador(nodo->izq) || tiene_negacion_sobre_operador(nodo->der);
}

//Calcula la potencia de 2^n donde n es la cantidad de atomos
int potencia(int base, int exponente) {
    int resultado = 1;
    for (int i = 0; i < exponente; i = i + 1) {
        resultado = resultado * base;
    }
    return resultado;
}

//Verifica si una formula es satisfacible o no
int es_satisfacible(struct Node* raiz) {
    int total_combinaciones = potencia(2, total_atomos);

    for (int valores_verdad = 0; valores_verdad < total_combinaciones; valores_verdad = valores_verdad + 1) {
        for (int i = 0; i < total_atomos; i = i + 1) {
            atomos[i].valor = (valores_verdad / potencia(2, i)) % 2;
        }
        if (evaluar(raiz)) {
            return 1; // satisfacible
        }
    }

    return 0; // no satisfacible
}


%}

%%



\$ {
    if (opened == 0) {
        opened = 1;
    } else if (opened == 1) {
        opened = 2;
    } else {
        printf("Error: Entrada contiene más de dos símbolos $...\n");
        exit(1);
    }
}

[a-z] {
    if (!verificar_dentro()) return 1;
    agregarAtomoUnico(yytext[0]);
    
    int idx = 0;
    for (int i = 0; i < total_atomos; i = i+1)
        if (atomos[i].nombre == yytext[0])
            idx = i;

    indice_atomico[token_count] = idx; // Guarda el índice del átomo leído
   
    return TOKEN_ATOM;
}

"\\wedge" {
    if (!verificar_dentro()) return 1;
    return TOKEN_AND;
}

"\\vee" {
    if (!verificar_dentro()) return 1;
    return TOKEN_OR;
}

"\\neg" {
    if (!verificar_dentro()) return 1;
    return TOKEN_NOT;
}

"\\rightarrow" {
    if (!verificar_dentro()) return 1;
    return TOKEN_IMPL;
}

"(" {
    if (!verificar_dentro()) return 1;
    return TOKEN_LPAREN;
}

")" {
    if (!verificar_dentro()) return 1;
    return TOKEN_RPAREN;
}

[ \t\n]+ {/*Elimina espacios, tabulaciones y saltos de linea*/ }

. {
    printf("ERROR: símbolo no reconocido '%s'\n", yytext);
    exit(1);
}

%%

// Verifica si un token es un operador
int es_operador(int t) {
    return t == TOKEN_NOT || t == TOKEN_AND || t == TOKEN_OR || t == TOKEN_IMPL;
}

int main(int argc, char *argv[]) {
    int token, last_token = -1, token_balance = 0; 

    if (argc != 1) {
        printf("Uso: %s < [archivo_entrada.txt]\n", argv[0]);
        return 1;
    }

    while ((token = yylex()) != 0) {
	
	if(token_count >= MAX_TOKENS){
	    printf("Error: demasiados tokens\n");
            return 1;
	}
	
	token_buffer[token_count] = token;
	token_count = token_count + 1;
	
        /* 1) CHECKEO EVITAR DOS ATOMOS SEGUIDOS pp o qq o rr */
        if (token == TOKEN_ATOM && last_token == TOKEN_ATOM) {
            printf("Error: No poner 2 atomos seguidos...\n");
            return 1;	 
        }

        /* 2) CHECKEO EVITAR DOS OPERADORES SEGUIDOS (permite ¬¬ y OpBinario¬) */
        if (es_operador(token) && es_operador(last_token) && (token != TOKEN_NOT)) {
            printf("Error: Secuencia de operadores no permitida\n");
            return 1;
        }

        /* 3) CHECKEO BALANCE DE PARENTESIS () == 0 */
        if (token == TOKEN_LPAREN)
            token_balance = token_balance + 1;
        else if (token == TOKEN_RPAREN) {
            token_balance = token_balance - 1;
            if (token_balance < 0) {
                printf("Error: Inicie con parentesis ( antes de )\n");
                return 1;
            }
        }

        /* 4) NO EMPEZAR CON UN OPERADOR AL INICIO: && O || O -> a excepcion de ¬ */
        if (last_token == -1 && es_operador(token) && token != TOKEN_NOT) {
            printf("Error: NO iniciar con un operador...\n");
            return 1;
        }

        /* 5) ATOMO SEGUIDO DE PARENTESIS ABIERTO p( */
        if (token == TOKEN_LPAREN && last_token == TOKEN_ATOM) {
            printf("Error: NO poner un atomo seguido de un ( \n");
            return 1;
        }

        /* 6) PARENTESIS DERECHO SEGUIDO DE ATOMO: )p */
        if (token == TOKEN_ATOM && last_token == TOKEN_RPAREN) {
            printf("Error: NO poner un parentesis ) seguido de un atomo \n");
            return 1;
        }

        /* 7) PARENTESIS ABIERTO SEGUIDO DE OPERADOR(&& pero (¬ si es valido */
        if (es_operador(token) && last_token == TOKEN_LPAREN && token != TOKEN_NOT) {
            printf("Error: PARENTESIS ( seguido de un operador binario\n");
            return 1;
        }
        
        /* 8) OPERADOR SEGUIDO DE UN PARENTESIS DERECHO &&)*/ 
	    if (es_operador(last_token) && token == TOKEN_RPAREN ) {
            printf("Error: NO poner un operador binario seguido de un )\n");
            return 1;
        }
	
	/*9) token not ¬ solo puede estar seguido de (¬patomo, parentesis abierto(¬ o negacion ¬ */	
	  if (last_token == TOKEN_NOT && !(token == TOKEN_ATOM || token == TOKEN_LPAREN || token == TOKEN_NOT)){
	    printf("ERROR: EL operador negacion ¬ solo puede estar seguido de un atomo, un parentesis abierto o una negacion...\n");
	    return 1;
	  }
	/*10) atomo no puede estar seguido de un negacion p¬ */  
	
	if(token == TOKEN_NOT && last_token == TOKEN_ATOM){
	  printf("ERROR: EL atomo no puede estar seguido de ¬ (p¬)...\n");
	  return 1;
	}
	
        /* 11) ¿PARENTESIS VACIO ()? */
        if (token == TOKEN_RPAREN && last_token == TOKEN_LPAREN) {
            printf("Error: NO se permiten parentesis vacios ()\n");
            return 1;
        }
         last_token = token;
}
        //verificaiones finales
        
        /*12) si el ultimo token es operador*/
        if(es_operador(last_token)){
         printf("La ultima palabra no puede ser un operador...\n");
         return 1;
        }
    	
    	/*13) ¿Parentesis balanceados? No tirar error */
    	if(token_balance != 0){
    	  printf("ERROR: Parentesis Desbalanceados...\n");
    	  return 1;
    	}
 	/* 14) Expresión vacía*/
	if (opened == 2 && last_token == -1) {
    	printf("ERROR: La expresión está vacía dentro de los delimitadores $...\n");
    	return 1;
	}
    	/*15) Entrada sin $*/
    	if(opened != 2){
    	    printf("ERROR: La expresión no está correctamente delimitada con $ al inicio y al final $ .\n");
    	    return 1;
    	}
    
    struct Node* arbol;
    arbol = parse_formula();
    

    
    return 0;
}

int yywrap() { return 1;}
