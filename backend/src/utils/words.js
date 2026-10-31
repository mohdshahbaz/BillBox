const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen',
  'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
const two = (n) => (n < 20 ? ones[n] : tens[Math.floor(n / 10)] + (n % 10 ? ' ' + ones[n % 10] : ''));
const three = (n) => (n >= 100 ? ones[Math.floor(n / 100)] + ' Hundred' + (n % 100 ? ' ' : '') : '') + (n % 100 ? two(n % 100) : '');

/** Indian numbering: Crore / Lakh / Thousand. */
function words(n) {
  if (n === 0) return 'Zero';
  const parts = [];
  const cr = Math.floor(n / 1e7), lk = Math.floor(n / 1e5) % 100, th = Math.floor(n / 1e3) % 100, rest = n % 1000;
  if (cr) parts.push(three(cr) + ' Crore');
  if (lk) parts.push(two(lk) + ' Lakh');
  if (th) parts.push(two(th) + ' Thousand');
  if (rest) parts.push(three(rest));
  return parts.join(' ');
}
/** "Rupees Two Thousand Five Hundred Only"; a total that is not rounded to the rupee also says its paise. */
const rupeesInWords = (total) => {
  const paise = Math.round(Math.abs(total) * 100) % 100;
  return paise ? `Rupees ${words(Math.floor(total))} and ${words(paise)} Paise Only` : `Rupees ${words(Math.round(total))} Only`;
};

module.exports = { words, rupeesInWords };
