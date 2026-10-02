import org.luaj.vm2.*;
import org.luaj.vm2.lib.jse.*;
import java.io.FileReader;

public class SyntaxCheck {
    public static void main(String[] args) throws Exception {
        String path = args.length > 0 ? args[0] : "/home/z/my-project/download/wtrlab.lua";
        Globals g = JsePlatform.standardGlobals();
        try {
            LuaValue chunk = g.load(new FileReader(path), path);
            chunk.call();
            System.out.println("SYNTAX OK");
            String[] fns = {"getCatalogList","getCatalogSearch","getCatalogFiltered","getBookTitle","getBookCoverImageUrl","getBookDescription","getBookGenres","getBookRating","getBookStatus","getBookLastUpdate","getChapterListHash","getChapterList","getChapterText","getSettingsSchema","getFilterList"};
            int ok = 0;
            for (String f : fns) { if (!g.get(f).isnil()) ok++; else System.out.println("MISSING: " + f); }
            System.out.println("functions: " + ok + "/15  version=" + g.get("version") + "  name=" + g.get("name"));
            System.out.println("cf_options " + (g.get("cf_options").isnil() ? "ABSENT (good)" : "PRESENT (BAD)"));
        } catch (Exception e) {
            System.out.println("SYNTAX FAIL: " + e.getMessage());
            System.exit(1);
        }
    }
}
