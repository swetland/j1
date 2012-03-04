// Copyright 2009-2012, Brian Swetland.  Use at your own risk.

// An assembler for the J1 CPU

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <ctype.h>

static FILE *fp;
static char *filename;
static char linestring[256];
static char linebuffer[256];
static unsigned linenumber = 0;

#define TRACE(x...) do {} while(0)

void die(const char *fmt, ...) {
	va_list ap;
	fprintf(stderr,"%s:%d: ", filename, linenumber);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr,"\n");
	if (linestring[0])
		fprintf(stderr,"%s:%d: >> %s <<\n", filename, linenumber, linestring);
	exit(1);
}

static unsigned PC = 0;
static uint16_t rom[8192];

struct fixup {
	struct fixup *next;
	unsigned pc;
};

struct label {
	struct label *next;
	struct fixup *fixups;
	unsigned pc;
	char name[1];
};

struct uprogram {
	struct uprogram *next;
	uint16_t op;
	char name[1];
};

struct uprogram *uprograms = NULL;
struct label *labels = NULL;
struct fixup *fixups = NULL;

void fixup_branch(const char *name, unsigned addr, unsigned target) {
	if (target > 0x1FFF)
		die("branch target 0x%x invalid\n", target);
	rom[addr] = (rom[addr] & 0xE000) | (target & 0x1FFF);
}

void setlabel(const char *name, unsigned pc) {
	struct label *l;
	struct fixup *f;

	for (l = labels; l; l = l->next) {
		if (!strcasecmp(l->name, name)) {
			if (l->pc != 0xFFFF)
				die("cannot redefine '%s'", name);
			TRACE("amend-def('%s',0x%x)\n",name,pc);
			l->pc = pc;
			for (f = l->fixups; f; f = f->next) {
				fixup_branch(name, f->pc, l->pc);
			}
			return;
		}
	}
	TRACE("define('%s',0x%x)\n",name,pc);
	l = malloc(sizeof(*l) + strlen(name));
	strcpy(l->name, name);
	l->pc = pc;
	l->fixups = 0;
	l->next = labels;
	labels = l;
}

const char *getlabel(unsigned pc) {
	struct label *l;
	for (l = labels; l; l = l->next)
		if (l->pc == pc)
			return l->name;
	return 0;
}

void uselabel(const char *name, unsigned pc) {
	struct label *l;
	struct fixup *f;

	for (l = labels; l; l = l->next) {
		if (!strcasecmp(l->name, name)) {
			TRACE("amend-ref('%s',0x%x)\n",name,pc);
			if (l->pc != 0xFFFF) {
				fixup_branch(name, pc, l->pc);
				return;
			} else {
				goto add_fixup;
			}
		}
	}
	TRACE("reference('%s',0x%x)\n",name,pc);
	l = malloc(sizeof(*l) + strlen(name));
	strcpy(l->name, name);
	l->pc = 0xFFFF;
	l->fixups = 0;
	l->next = labels;
	labels = l;
add_fixup:
	TRACE("addfixup('%s',0x%x)\n",name,pc);
	f = malloc(sizeof(*f));
	f->pc = pc;
	f->next = l->fixups;
	l->fixups = f;
}

void checklabels(void) {
	struct label *l;
	for (l = labels; l; l = l->next)
		if (l->pc == 0xFFFF)
			die("undefined label '%s'", l->name);
}

void emit(uint16_t word) {
	rom[PC++] = word;
}

void disassemble(char *buf, unsigned pc, unsigned op);

void save(const char *fn) {
	const char *name;
	unsigned n;
	char dis[128];
	FILE *fp = fopen(fn, "w");
	if (!fp) die("cannot write to '%s'", fn);
	for (n = 0; n < PC; n++) {
		disassemble(dis, n * 2, rom[n]);
		name = getlabel(n);
		if (name) {
			fprintf(fp, "%04x  // %04x: %-25s <- %s\n", rom[n], n*2, dis, name);
		} else {
			fprintf(fp, "%04x  // %04x: %s\n", rom[n], n*2, dis);
		}
	}
	fclose(fp);
}

static char *next_saveptr = NULL;
static char *END = "";

char *next(void) {
	char *x;
	if (fp == 0)
		return END;
	if (next_saveptr == NULL) {
again:
		x = fgets(linebuffer, sizeof(linebuffer), fp);
		if (x == NULL) {
			fclose(fp);
			fp = NULL;
			return END;
		}
		memcpy(linestring, linebuffer, sizeof(linebuffer));
		linenumber++;
		TRACE("%5d: %s",linenumber,linebuffer);
		x = strtok_r(linebuffer, " \t\r\n", &next_saveptr);
	} else {
		x = strtok_r(NULL, " \t\r\n", &next_saveptr);
	}
	if (x == NULL)
		goto again;
	return x;
}

uint16_t to_u16(char *in) {
	unsigned n;
	
	if (!isdigit(in[0]) && (in[0] != '-'))
		die("'%s' is not a number", in);

	n = strtoul(in, NULL, 0);
	if ((n & 0xFFFF0000) && (!(n & 0xFFFF8000)))
		die("%d is not a 16bit number", n);
	return (uint16_t) n;
}

struct uop {
	uint16_t op;
	char *name;
};

struct uop UOP[] = {
	{ 0x6000, "ALU" },

	{ 0x1000, "R->PC" },
	{ 0x0080, "T->N" },
	{ 0x0040, "T->R" },
	{ 0x0020, "N->[T]" },
	{ 0x0004, "R+" },
	{ 0x000C, "R-" },
	{ 0x0008, "R-2" },
	{ 0x0001, "D+" },
	{ 0x0003, "D-" },
	{ 0x0002, "D-2" },

	{ 0x0000, "T" },
	{ 0x0100, "N" },
	{ 0x0200, "T+N" },
	{ 0x0300, "T&N" },
	{ 0x0400, "T|N" },
	{ 0x0500, "T^N" },
	{ 0x0600, "~T" },
	{ 0x0700, "N==T" },
	{ 0x0800, "N<T" },
	{ 0x0900, "N>>T" },
	{ 0x0A00, "T-1" },
	{ 0x0B00, "R" },
	{ 0x0C00, "[T]" },
	{ 0x0D00, "N<<T" },
	{ 0x0E00, "dsp" },
	{ 0x0F00, "Nu<T" },
};

void disassemble(char *buf, unsigned pc, unsigned op) {
	struct uprogram *up;
	int has_return = 0;
	if (op & 0x8000) {
		sprintf(buf, "PUSH %d", op & 0x7FFF);
		return;
	}
	switch (op & 0xE000) {
	case 0x0000:
		sprintf(buf, "JUMP 0x%04x", (op & 0x1FFF) * 2);
		return;
	case 0x2000:
		sprintf(buf, "JUMPZ 0x%04x", (op & 0x1FFF) * 2);
		return;
	case 0x4000:
		sprintf(buf, "CALL 0x%04x", (op & 0x1FFF) * 2);
		return;
	case 0x6000:
		if ((op & 0x104C) == 0x100C) {
			if (op != 0x700C) {
				has_return = 1;
				op &= (~0x104C);
			}
		}
		for (up = uprograms; up; up = up->next) {
			if (up->op == op) {
				sprintf(buf,"%s%s", up->name, has_return ? ", RETURN" : "");
				return;
			}
		}
		if (has_return) {
			sprintf(buf,"RETURN");
			return;
		}
	}
	sprintf(buf,"???");
}

void assemble_microprogram(void) {
	char *name;
	char *tok;
	struct uprogram *up;
	uint16_t op = 0;
	int n;

	name = strdup(next());
	if (name == END)
		die("EOF while defining microprogram");

again:
	for (;;) {
		tok = next();
		if (!strcmp(tok,">>")) break;
		for (n = 0; n < (sizeof(UOP)/sizeof(UOP[0])); n++) {
			if (!strcasecmp(UOP[n].name,tok)) {
				op |= UOP[n].op;
				goto again;
			}
		}
		op |= to_u16(tok);
	}

	up = malloc(sizeof(*up) + strlen(name));
	strcpy(up->name, name);
	up->op = op;
	up->next = uprograms;
	uprograms = up;
	free(name);
}

void assemble_branch(uint16_t op) {
	char *tok = next();
	if (tok == END)
		die("EOF?");
	if (!strcmp(tok,".")) {
		emit(op | PC);
	} else {
		emit(op);
		uselabel(tok, PC - 1);
	}
}
	
void assemble(void) {
	char *tok;
	uint16_t n;
	struct uprogram *up;

again:
	while ((tok = next()) != END) {
		if (!strcmp(tok,"(")) {
			for (;;) {
				tok = next();
				if (tok == END)
					die("unterminated comment");
				if (!strcmp(tok,")"))
					break;
			}
		} else if (!strcmp(tok,"<<")) {
			assemble_microprogram();
		} else if (!strcmp(tok,":")) {
			tok = next();
			if (tok == END)
				die("EOF?");
			setlabel(tok,PC);
		} else if (!strcasecmp(tok,"CALL")) {
			assemble_branch(0x4000);
		} else if (!strcasecmp(tok,"B")) {
			assemble_branch(0x0000);
		} else if (!strcasecmp(tok,"BZ")) {
			assemble_branch(0x2000);
		} else if (!strcasecmp(tok,"PUSH")) {
			tok = next();
			if (tok == END)
				die("EOF?");
			/* todo label references */
			n = to_u16(tok);
			if (n & 0x8000) {
				emit(0x8000 | (~n));
				emit(0x6600); // T=~T
			} else {
				emit(0x8000 | n);
			}
		} else if (!strcasecmp(tok,"STORE")) {
			emit(0x6123); /* ALU N D- N->[T] */
			emit(0x6103); /* ALU D- */
		} else if (!strcasecmp(tok,"LOAD")) {
			emit(0x6000); /* ALU T */
			emit(0x6c00); /* ALU [T] */
		} else if (!strcasecmp(tok,"RETURN")) {
			uint16_t op;
			if (PC == 0) die("wtf");
			op = rom[PC-1];
			if ((op & 0xF04C) == 0x6000) {
				/* if ALU op that doesn't touch R */
				/* we can fold the return in */
				rom[PC-1] |= 0x100C;
			} else if ((op & 0xE000) == 0x4000) {
				/* convert CALL to JUMP */	
				rom[PC-1] &= (~0x4000);
			} else {
				emit(0x700C);
			}
		} else {
			for (up = uprograms; up; up = up->next) {
				if (!strcasecmp(tok, up->name)) {
					emit(up->op);
					goto again;
				}
			}
			die("cannot process '%s'", tok);
		} 
	}
}

int main(int argc, char **argv) {
	const char *outname = "out.hex";

	argc--;
	argv++;

	filename = "unknown";

	while (argc > 0) {
		if (!strcmp(argv[0],"-o")) {
			if (argc < 2)
				die("no output file?");
			outname = argv[1];
			argc--;
			argv++;
		} else {
			filename = argv[0];
			linenumber = 0;
			if ((fp = fopen(filename, "r")) == 0)
				die("cannot open '%s'", filename);
			assemble();
		}
		argc--;
		argv++;
	}
	
	assemble();
	if (PC == 0) {
		fprintf(stderr,"usage: a1 [ -o <output> ] <source>*\n");
		return -1;
	}

	checklabels();
	save(outname);
	return 0;
}

