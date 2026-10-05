#!/usr/bin/env bash
# skills/collective/dnp-scan.sh: the do-not-post scan (CONTRACT 5.7, COL-7).
#
#   dnp-scan.sh < draft-post.md
#
# Reads a draft post on stdin (first 1 MiB) and exits 1 if it matches any
# do-not-post category, printing one "DNP <CATEGORY> (line <n>)" per hit and
# never the matched text. Exit 0 means no category matched. Categories:
#   PAY                pay, salary, compensation, money tied to pay words
#   HEALTH             diagnoses, prescriptions, dosages, ICD-10 codes, ratings
#   FAMILY-PII         birth dates, street addresses, phone numbers, a child
#                      named together with a school
#   CREDENTIAL         passwords, API keys, tokens, private keys
#   FINANCIAL-ACCOUNT  account, routing, card and IBAN numbers, wallet phrases
#   GOV-ID             SSNs and numbered government IDs
# Pattern classes only: this plugin is generic, so no real name, address or
# number appears here (GAP-36). A hit blocks the post until the human edits
# it or explicitly overrides this category for this one post.
LC_ALL=C; export LC_ALL

input=$(head -c 1048576)

W='(^|[^A-Za-z0-9_])'
E='([^A-Za-z0-9_]|$)'
hits=0

# check CATEGORY MODE ERE...: MODE i = case-insensitive, s = case-sensitive.
# One grep decides; a second, only on a hit, finds the line numbers.
check() {
  local cat=$1 mode=$2 flags=-E lines
  local args
  shift 2
  [ "$mode" = i ] && flags=-Ei
  args=()
  while [ $# -gt 0 ]; do args+=(-e "$1"); shift; done
  grep $flags -q "${args[@]}" <<<"$input" || return 1
  lines=$(grep $flags -n "${args[@]}" <<<"$input" | cut -d: -f1 | head -3 | tr '\n' ' ')
  printf 'DNP %s (line %s)\n' "$cat" "${lines% }"
  hits=1
  return 0
}

# PAY
check PAY i \
  "${W}(salary|salaries|paycheck|pay ?stub|payslip|pay rate|hourly rate|compensation|severance|offer letter|w-2|1099-nec)${E}" \
  "${W}(bonus|raise|wages?|base pay|take-home|rsus?|equity grant)[^.]{0,40}[\$][ ]?[0-9]" \
  "[\$][ ]?[0-9][0-9,.]*k?[ ]?(/|a|per) ?(year|yr|hour|hr|month|mo)${E}" \
  "${W}[0-9]{2,3}k (a|per) year${E}"

# HEALTH
check HEALTH i \
  "${W}(diagnos(is|ed|es)|prescri(ption|bed)|medications?|dosage|therap(y|ist)|psychiatri(c|st)|surgery|chemotherapy|blood pressure|pregnan(t|cy)|miscarriage|medical records?|disability rating|service-connected|ptsd|adhd|major depressive|anxiety disorder|insulin|antidepressants?)${E}" \
  "${W}[0-9]+ ?mg${E}" ||
check HEALTH s \
  "(^|[^A-Za-z0-9_.])[A-TW-Z][0-9][0-9]\.[0-9A-Z]{1,4}([^A-Za-z0-9_.]|$)"

# FAMILY-PII
child_school() {
  grep -Eiq "${W}(sons?|daughters?|kids?|child|children|stepsons?|stepdaughters?)${E}" <<<"$input" &&
    grep -Eiq "${W}(school|elementary|kindergarten|preschool|daycare|teacher|[0-9]+(st|nd|rd|th) grade|class of [0-9]{4})${E}" <<<"$input" ||
    return 1
  echo "DNP FAMILY-PII (a child named together with a school)"
  hits=1
}
check FAMILY-PII i \
  "${W}(dob|date of birth|birth ?date|born( on)?)[: ]+([0-9]{1,2}[/-][0-9]{1,2}[/-][0-9]{2,4}|[0-9]{4}-[0-9]{2}-[0-9]{2}|(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.? [0-9]{1,2})" \
  "${W}p\.? ?o\.? box [0-9]+" \
  "(^|[^0-9])(\+?1[ .-]?)?\(?[2-9][0-9]{2}\)?[ .-][0-9]{3}[ .-][0-9]{4}([^0-9]|$)" ||
check FAMILY-PII s \
  "(^|[^0-9])[0-9]{1,6} ([A-Z][a-z]+ ){1,3}(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl|Terrace|Circle|Cir|Parkway|Pkwy|Highway|Hwy)\.?([^A-Za-z]|$)" ||
child_school

# CREDENTIAL
check CREDENTIAL i \
  "${W}(password|passwd|passcode)[ ]*[:=][ ]*[^ ]" \
  "${W}(api[_-]?key|secret[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|bearer)[\"' ]*[:= ][ \"']*[A-Za-z0-9_./+=-]{16,}" \
  "-----BEGIN [A-Z ]*PRIVATE KEY-----" ||
check CREDENTIAL s \
  "(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35})"

# FINANCIAL-ACCOUNT
check FINANCIAL-ACCOUNT i \
  "${W}(routing|aba)( number| no\.?| #)?[: #]+[0-9]{9}([^0-9]|$)" \
  "${W}(account|acct)( number| no\.?| #)?[: #]+[0-9][0-9 -]{4,}[0-9]" \
  "(^|[^0-9])[0-9]{4}[ -]?[0-9]{4}[ -]?[0-9]{4}[ -]?[0-9]{1,7}([^0-9]|$)" \
  "${W}iban[: ]+[a-z]{2}[0-9]{2}" \
  "${W}(seed phrase|recovery phrase|mnemonic phrase)[: ]"

# GOV-ID
check GOV-ID s \
  "(^|[^0-9-])[0-9]{3}-[0-9]{2}-[0-9]{4}([^0-9-]|$)" ||
check GOV-ID i \
  "${W}(ssn|social security( number| no\.?)?|passport( number| no\.?| #)?|driver'?s? licen[cs]e( number| no\.?| #)?|ein|tax id|itin|va file( number| no\.?)?|dod id|military id)[: #]+[a-z]{0,2}[0-9][0-9-]{4,}"

exit "$hits"
