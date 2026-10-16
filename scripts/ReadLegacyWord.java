import java.io.*;
import java.nio.charset.StandardCharsets;
import javax.xml.stream.*;
import org.apache.poi.hwpf.HWPFDocument;
import org.apache.poi.hwpf.usermodel.*;

/** Read bounded cell text only; never open Office, external links, or macros. */
public final class ReadLegacyWord {
    private static long characters = 0;
    private static String text(String value) {
        String clean = value.replaceAll("[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]", " ");
        if (clean.length() > 8000 || (characters += clean.length()) > 12000000)
            throw new IllegalArgumentException("document_text_limit");
        return clean;
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 2 || new File(args[0]).length() > 5000000)
            throw new IllegalArgumentException("document_size_limit");
        try (InputStream input = new FileInputStream(args[0]); HWPFDocument doc = new HWPFDocument(input); OutputStream output = new FileOutputStream(args[1])) {
            Range range = doc.getRange();
            if (range.numParagraphs() > 30000) throw new IllegalArgumentException("paragraph_limit");
            XMLStreamWriter xml = XMLOutputFactory.newFactory().createXMLStreamWriter(output, "UTF-8");
            xml.writeStartDocument("UTF-8", "1.0"); xml.writeStartElement("document");
            xml.writeStartElement("title");
            for (int p = 0; p < Math.min(12, range.numParagraphs()); p++) {
                if (range.getParagraph(p).isInTable()) break;
                xml.writeCharacters(text(range.getParagraph(p).text()));
            }
            xml.writeEndElement();
            TableIterator iterator = new TableIterator(range); int count = 0;
            while (iterator.hasNext()) {
                if (++count > 100) throw new IllegalArgumentException("table_count_limit");
                Table table = iterator.next();
                if (table.numRows() > 3000) throw new IllegalArgumentException("table_row_limit");
                xml.writeStartElement("table");
                for (int r = 0; r < table.numRows(); r++) {
                    TableRow row = table.getRow(r);
                    if (row.numCells() > 60) throw new IllegalArgumentException("table_column_limit");
                    xml.writeStartElement("row");
                    for (int c = 0; c < row.numCells(); c++) {
                        xml.writeStartElement("cell"); xml.writeCharacters(text(row.getCell(c).text())); xml.writeEndElement();
                    }
                    xml.writeEndElement();
                }
                xml.writeEndElement();
            }
            xml.writeEndElement(); xml.writeEndDocument(); xml.flush();
        }
    }
}
