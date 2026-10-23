// ExportAllDecompiled.java — vuelca el C decompilado de TODAS las funciones a ficheros.
// Uso: analyzeHeadless <projdir> <projname> -process msm_drm.ko -postScript ExportAllDecompiled.java <outdir> [filtro]
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.util.*;

public class ExportAllDecompiled extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String outDir = a.length > 0 ? a[0] : "/tmp/opencode/decomp";
        String filter = a.length > 1 ? a[1] : "";
        File od = new File(outDir);
        od.mkdirs();

        DecompInterface di = new DecompInterface();
        di.setOptions(new DecompileOptions());
        di.toggleCCode(true);
        di.toggleSyntaxTree(true);
        di.setSimplificationStyle("decompile");
        if (!di.openProgram(currentProgram)) { println("ERROR: no se pudo abrir el programa"); return; }

        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        int total = 0, written = 0, failed = 0;
        while (it.hasNext()) {
            Function f = it.next();
            if (f.isExternal() || f.isThunk()) continue;
            String name = (f.getSymbol() != null) ? f.getSymbol().getName() : f.getName();
            if (!filter.isEmpty() && !name.toLowerCase().contains(filter.toLowerCase())) continue;
            total++;
            try {
                DecompileResults r = di.decompileFunction(f, 120, monitor);
                if (r != null && r.decompileCompleted() && r.getDecompiledFunction() != null) {
                    String safe = name.replaceAll("[^A-Za-z0-9_.-]", "_");
                    try (PrintWriter pw = new PrintWriter(new File(od, safe + ".c"))) {
                        pw.print("/* " + f.getEntryPoint() + "  bytes=" + f.getBody().getNumAddresses() + " */\n");
                        pw.print(r.getDecompiledFunction().getC());
                    }
                    written++;
                    if (written % 250 == 0) println("  ... " + written);
                } else failed++;
            } catch (Exception e) { failed++; }
        }
        di.dispose();
        try (PrintWriter pw = new PrintWriter(new File(od, "_INDEX.txt"))) {
            pw.println("total=" + total + " written=" + written + " failed=" + failed);
        }
        println("LISTO total=" + total + " written=" + written + " failed=" + failed + " -> " + outDir);
    }
}