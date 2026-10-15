#include <stdio.h>
static char* conv(unsigned long long v, int neg, char* b, int base){ char t[70]; int i=0; do{ int d=v%base; t[i++]=d<10?'0'+d:'a'+d-10; v/=base;}while(v); int k=0; if(neg) b[k++]='-'; while(i) b[k++]=t[--i]; b[k]=0; return b; }
char* itoa(int v, char* b, int base){ return v<0&&base==10?conv(-(long long)v,1,b,base):conv((unsigned)v,0,b,base); }
char* utoa(unsigned v, char* b, int base){ return conv(v,0,b,base); }
