package com.donation.platform.service;

import com.donation.platform.entity.Donation;
import com.donation.platform.entity.Receipt;
import com.lowagie.text.*;
import com.lowagie.text.pdf.*;
import com.lowagie.text.pdf.draw.LineSeparator;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.math.BigDecimal;
import java.time.format.DateTimeFormatter;

@Service
@Slf4j
public class ReceiptPdfService {

    @Value("${app.organization.name:ImpactFund Humanitarian Foundation}")
    private String orgName;

    @Value("${app.organization.registration-number:NGO-MH-2023-889971}")
    private String orgRegNo;

    @Value("${app.organization.pan:AAATI9981K}")
    private String orgPan;

    @Value("${app.organization.section80g-number:CIT(E)/80G/2023-24/A/10042}")
    private String section80gNo;

    @Value("${app.organization.address:Level 5, Impact Towers, BKC, Mumbai - 400051, India}")
    private String orgAddress;

    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern("dd-MMM-yyyy HH:mm:ss 'IST'");

    /**
     * Programmatically generates a formal, legally compliant 80G tax-exempt donation certificate
     * in PDF format using OpenPDF without external binary dependencies.
     */
    public byte[] generate80GReceiptPdf(Receipt receipt, Donation donation) {
        log.info("Generating 80G PDF receipt for receipt number: {}", receipt.getReceiptNumber());

        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Document document = new Document(PageSize.A4, 36, 36, 36, 36);
            PdfWriter writer = PdfWriter.getInstance(document, out);
            document.open();

            // Color Palette
            Color brandEmerald = new Color(5, 150, 105);
            Color darkSlate = new Color(15, 23, 42);
            Color borderGray = new Color(226, 232, 240);
            Color lightGray = new Color(248, 250, 252);
            Color textMuted = new Color(100, 116, 139);

            // Fonts
            Font fontHeaderOrg = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 18, brandEmerald);
            Font fontSubOrg = FontFactory.getFont(FontFactory.HELVETICA, 8, textMuted);
            Font fontTitle = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 14, darkSlate);
            Font fontSubtitle = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 9, brandEmerald);
            Font fontLabel = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 9, darkSlate);
            Font fontValue = FontFactory.getFont(FontFactory.HELVETICA, 9, darkSlate);
            Font fontNotice = FontFactory.getFont(FontFactory.HELVETICA_OBLIQUE, 8, textMuted);
            Font fontAmountBold = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 12, brandEmerald);

            // 1. Organization Header Table
            PdfPTable headerTable = new PdfPTable(1);
            headerTable.setWidthPercentage(100);

            PdfPCell cellOrg = new PdfPCell();
            cellOrg.setBorder(Rectangle.NO_BORDER);
            cellOrg.setHorizontalAlignment(Element.ALIGN_CENTER);
            cellOrg.addElement(new Paragraph(orgName.toUpperCase(), fontHeaderOrg));
            cellOrg.addElement(new Paragraph(orgAddress, fontSubOrg));
            cellOrg.addElement(new Paragraph("Govt Registration No: " + orgRegNo + "  |  Trust PAN: " + orgPan, fontSubOrg));
            cellOrg.addElement(new Paragraph("Income Tax 80G Approval Certificate: " + section80gNo, fontSubtitle));
            headerTable.addCell(cellOrg);
            document.add(headerTable);

            document.add(new Paragraph(" "));
            LineSeparator sep = new LineSeparator(1.5f, 100, brandEmerald, Element.ALIGN_CENTER, -2);
            document.add(sep);
            document.add(new Paragraph(" "));

            // 2. Receipt Certificate Title
            Paragraph title = new Paragraph("CERTIFICATE OF DONATION (SECTION 80G)", fontTitle);
            title.setAlignment(Element.ALIGN_CENTER);
            document.add(title);

            Paragraph taxNote = new Paragraph("Eligible for 50% Tax Exemption under Section 80G of the Income Tax Act, 1961", fontNotice);
            taxNote.setAlignment(Element.ALIGN_CENTER);
            document.add(taxNote);

            document.add(new Paragraph(" "));

            // 3. Receipt Details Table
            PdfPTable detailsTable = new PdfPTable(4);
            detailsTable.setWidthPercentage(100);
            detailsTable.setWidths(new float[]{22f, 28f, 22f, 28f});
            detailsTable.getDefaultCell().setPadding(6);

            addTableCell(detailsTable, "Receipt No:", fontLabel, lightGray, false);
            addTableCell(detailsTable, receipt.getReceiptNumber(), fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Date Issued:", fontLabel, lightGray, false);
            addTableCell(detailsTable, receipt.getIssuedAt().format(DATE_FORMATTER), fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Donor Name:", fontLabel, lightGray, false);
            addTableCell(detailsTable, receipt.getDonorName(), fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Donor PAN / Tax ID:", fontLabel, lightGray, false);
            String panText = (receipt.getDonorPan() != null && !receipt.getDonorPan().isBlank())
                    ? receipt.getDonorPan()
                    : "Not Provided / Anonymous";
            addTableCell(detailsTable, panText, fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Donor Email:", fontLabel, lightGray, false);
            addTableCell(detailsTable, receipt.getDonorEmail(), fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Payment Gateway:", fontLabel, lightGray, false);
            addTableCell(detailsTable, "Razorpay (Online Transfer)", fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Razorpay Order ID:", fontLabel, lightGray, false);
            addTableCell(detailsTable, donation.getRazorpayOrderId(), fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Razorpay Payment ID:", fontLabel, lightGray, false);
            addTableCell(detailsTable, donation.getRazorpayPaymentId(), fontValue, Color.WHITE, false);

            addTableCell(detailsTable, "Campaign Cause:", fontLabel, lightGray, false);
            PdfPCell causeCell = new PdfPCell(new Phrase(receipt.getCampaignTitle(), fontValue));
            causeCell.setColspan(3);
            causeCell.setPadding(6);
            causeCell.setBorderColor(borderGray);
            detailsTable.addCell(causeCell);

            document.add(detailsTable);
            document.add(new Paragraph(" "));

            // 4. Financial Amount Table
            PdfPTable amountTable = new PdfPTable(2);
            amountTable.setWidthPercentage(100);
            amountTable.setWidths(new float[]{30f, 70f});
            amountTable.getDefaultCell().setPadding(8);

            addTableCell(amountTable, "Amount Contributed:", fontLabel, lightGray, true);
            addTableCell(amountTable, "INR ₹" + receipt.getAmount().toPlainString(), fontAmountBold, Color.WHITE, true);

            addTableCell(amountTable, "Amount in Words:", fontLabel, lightGray, true);
            addTableCell(amountTable, convertAmountToWords(receipt.getAmount()), fontValue, Color.WHITE, true);

            document.add(amountTable);
            document.add(new Paragraph(" "));

            // 5. Terms & Statutory Declaration
            PdfPTable termsTable = new PdfPTable(1);
            termsTable.setWidthPercentage(100);
            PdfPCell termsCell = new PdfPCell();
            termsCell.setBackgroundColor(lightGray);
            termsCell.setBorderColor(borderGray);
            termsCell.setPadding(8);

            Paragraph declHeader = new Paragraph("STATUTORY DECLARATION & TERMS:", fontLabel);
            Paragraph declBody = new Paragraph(
                    "1. This receipt is digitally generated and signed electronically upon cryptographic verification of payment via Razorpay.\n" +
                    "2. No commercial goods or services were provided in exchange for this contribution.\n" +
                    "3. Donations are eligible for tax deductions under Section 80G(5)(vi) of the Income Tax Act, 1961.\n" +
                    "4. For any verification or tax reconciliation inquiries, please quote the Receipt Number.",
                    fontNotice
            );
            termsCell.addElement(declHeader);
            termsCell.addElement(declBody);
            termsTable.addCell(termsCell);
            document.add(termsTable);

            document.add(new Paragraph(" "));
            document.add(new Paragraph(" "));

            // 6. Signature & Digital Seal Block
            PdfPTable sigTable = new PdfPTable(2);
            sigTable.setWidthPercentage(100);
            sigTable.setWidths(new float[]{60f, 40f});

            PdfPCell cellLeft = new PdfPCell();
            cellLeft.setBorder(Rectangle.NO_BORDER);
            cellLeft.addElement(new Paragraph("Issued on behalf of:", fontNotice));
            cellLeft.addElement(new Paragraph(orgName, fontLabel));
            cellLeft.addElement(new Paragraph("Electronic Verification Authority", fontNotice));
            sigTable.addCell(cellLeft);

            PdfPCell cellRight = new PdfPCell();
            cellRight.setBorder(Rectangle.NO_BORDER);
            cellRight.setHorizontalAlignment(Element.ALIGN_RIGHT);
            Paragraph sigLine = new Paragraph("[ Digitally Authorized Signatory ]\nFinance & Accounts Department", fontLabel);
            sigLine.setAlignment(Element.ALIGN_RIGHT);
            cellRight.addElement(sigLine);
            sigTable.addCell(cellRight);

            document.add(sigTable);

            document.close();
            log.info("Successfully generated 80G PDF receipt ({} bytes)", out.size());
            return out.toByteArray();

        } catch (Exception e) {
            log.error("Failed to generate PDF receipt for receipt {}: {}", receipt.getReceiptNumber(), e.getMessage(), e);
            throw new RuntimeException("PDF Generation failed: " + e.getMessage(), e);
        }
    }

    private void addTableCell(PdfPTable table, String text, Font font, Color bgColor, boolean border) {
        PdfPCell cell = new PdfPCell(new Phrase(text, font));
        cell.setBackgroundColor(bgColor);
        cell.setPadding(6);
        cell.setBorderColor(new Color(226, 232, 240));
        if (!border) {
            cell.setBorder(Rectangle.BOX);
        }
        table.addCell(cell);
    }

    /**
     * Converts numerical INR currency to formal words in Indian numbering system.
     */
    public static String convertAmountToWords(BigDecimal amount) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            return "Zero Rupees Only";
        }

        long rupees = amount.longValue();
        int paise = amount.remainder(BigDecimal.ONE).multiply(BigDecimal.valueOf(100)).intValue();

        String words = convertNumberToWords(rupees) + " Rupees";
        if (paise > 0) {
            words += " and " + convertNumberToWords(paise) + " Paise";
        }
        return words + " Only";
    }

    private static final String[] UNITS = {
            "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
            "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
            "Seventeen", "Eighteen", "Nineteen"
    };

    private static final String[] TENS = {
            "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"
    };

    private static String convertNumberToWords(long n) {
        if (n == 0) return "Zero";
        if (n < 0) return "Minus " + convertNumberToWords(-n);

        if (n < 20) return UNITS[(int) n];
        if (n < 100) return TENS[(int) (n / 10)] + ((n % 10 != 0) ? " " + UNITS[(int) (n % 10)] : "");
        if (n < 1000) return UNITS[(int) (n / 100)] + " Hundred" + ((n % 100 != 0) ? " and " + convertNumberToWords(n % 100) : "");
        if (n < 100000) return convertNumberToWords(n / 1000) + " Thousand" + ((n % 1000 != 0) ? " " + convertNumberToWords(n % 1000) : "");
        if (n < 10000000) return convertNumberToWords(n / 100000) + " Lakh" + ((n % 100000 != 0) ? " " + convertNumberToWords(n % 100000) : "");

        return convertNumberToWords(n / 10000000) + " Crore" + ((n % 10000000 != 0) ? " " + convertNumberToWords(n % 10000000) : "");
    }
}
