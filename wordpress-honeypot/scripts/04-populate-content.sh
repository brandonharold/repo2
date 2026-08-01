#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:?}"
SITE_TITLE="${SITE_TITLE:?}"
WP_ROOT="${WP_ROOT:-/var/www/${DOMAIN}}"
WP="sudo -u www-data wp --path=${WP_ROOT}"

$WP theme install twentytwentyfour --activate

$WP option update blogdescription "Practical guidance for growing businesses."
$WP option update timezone_string "America/New_York"

# Clear out the default sample content.
$WP post delete "$($WP post list --post_type=post --field=ID --posts_per_page=1)" --force 2>/dev/null || true
for id in $($WP post list --post_type=page --field=ID); do
  $WP post delete "$id" --force
done

home_id=$($WP post create --post_type=page --post_title="Home" --post_status=publish --porcelain <<'EOF'
Welcome to Summit Business Solutions. We help small and mid-sized companies
streamline operations, plan for growth, and make confident decisions with
better data.

For over a decade our team has partnered with local businesses across the
region to deliver practical, right-sized consulting — no jargon, no
one-size-fits-all playbooks.

Explore our Services page to see how we can help, or get in touch through
our Contact page to schedule a free initial consultation.
EOF
)

about_id=$($WP post create --post_type=page --post_title="About Us" --post_status=publish --porcelain <<'EOF'
Summit Business Solutions was founded to give small businesses access to the
same caliber of strategic and operational advice larger companies take for
granted.

Our team brings backgrounds in operations, finance, and process improvement.
We work closely with each client to understand their goals before proposing
a single recommendation, and we measure our success by our clients' results,
not billable hours.

We are proud to have supported dozens of local businesses through periods of
growth, transition, and change.
EOF
)

services_id=$($WP post create --post_type=page --post_title="Services" --post_status=publish --porcelain <<'EOF'
Operations Consulting
We review your current processes and identify practical improvements that
save time and reduce cost, without disrupting day-to-day work.

Financial Planning
From cash flow forecasting to budgeting support, we help you understand
where your business stands and where it's headed.

Growth Strategy
Whether you're opening a second location or entering a new market, we help
you plan the next step with confidence.

Process Improvement
We help teams cut out repetitive, error-prone manual work and put
lightweight, sustainable systems in place.
EOF
)

blog_id=$($WP post create --post_type=page --post_title="Blog" --post_status=publish --porcelain <<'EOF'
Recent articles and updates from our team.
EOF
)

contact_id=$($WP post create --post_type=page --post_title="Contact" --post_status=publish --porcelain <<'EOF'
We'd love to hear from you.

Phone: (555) 010-0142
Email: hello@example.com
Hours: Monday–Friday, 9am–5pm

Our office is open by appointment. Reach out to schedule a free initial
consultation.
EOF
)

$WP option update show_on_front page
$WP option update page_on_front "$home_id"
$WP option update page_for_posts "$blog_id"

$WP post create --post_type=post --post_status=publish \
  --post_title="Five Signs Your Business Has Outgrown Its Current Processes" --porcelain <<'EOF'
Growth is a good problem to have, but it exposes cracks in processes that
worked fine at a smaller scale. Here are five signs it's time for a closer
look: recurring bottlenecks around the same one or two people, spreadsheets
that have become mission-critical, decisions that take longer than they
used to, onboarding that takes weeks instead of days, and a growing gap
between what leadership believes is happening and what's actually happening
day to day.
EOF

$WP post create --post_type=post --post_status=publish \
  --post_title="A Simple Framework for Cash Flow Forecasting" --porcelain <<'EOF'
Cash flow forecasting doesn't need to be complicated to be useful. Start
with a rolling 13-week view, separate recurring from one-time items, and
revisit your assumptions weekly rather than monthly. The goal isn't
precision — it's an early warning system for the weeks where cash gets
tight, so you can act before it becomes a crisis.
EOF

$WP post create --post_type=post --post_status=publish \
  --post_title="What We Look for in the First 30 Days With a New Client" --porcelain <<'EOF'
Before recommending any changes, we spend the first month simply listening
and observing: shadowing key workflows, reviewing existing reporting, and
talking to the people closest to the work. Most of the improvements we
eventually recommend come directly from that first month, not from a
generic playbook.
EOF

menu_id=$($WP menu list --fields=term_id --format=csv | tail -n1)
if [[ -z "$menu_id" ]]; then
  menu_id=$($WP menu create "Primary" --porcelain)
fi
$WP menu item add-post "$menu_id" "$home_id" --title="Home"
$WP menu item add-post "$menu_id" "$about_id" --title="About"
$WP menu item add-post "$menu_id" "$services_id" --title="Services"
$WP menu item add-post "$menu_id" "$blog_id" --title="Blog"
$WP menu item add-post "$menu_id" "$contact_id" --title="Contact"
$WP menu location assign "$menu_id" primary 2>/dev/null || true

$WP rewrite structure '/%postname%/' --hard
