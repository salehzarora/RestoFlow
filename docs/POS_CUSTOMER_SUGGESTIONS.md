# POS customer suggestions

Cashiers can type two name characters or four leading phone digits in the cart.
After a 300 ms pause the POS shows up to five branch contacts, with the last
four phone digits visible. Selecting a row fills both editable order fields.
The name and phone rules for submitting an order still apply. When the till
is offline or lookup is unavailable, the cashier can enter both fields by hand.

## Directory and access

The server derives a contact from a newly accepted POS `order.submit` after
the canonical order has its name and phone. Offline orders become eligible
after synchronization. A replay, rejected order, unsent cart, kiosk checkout
or storefront conversion does not add a contact. There is no historical import.
A directory write failure leaves the accepted order intact. A later eligible
order can remember that contact.

A private table stores one display name and phone per branch and normalized
name/phone pair. Name keys fold whitespace and case. Phone keys remove display
punctuation, preserving leading digits. Distinct names sharing a phone and
distinct phones sharing a name are separate suggestions. Search accepts Arabic,
Persian and ASCII phone digits and does not infer a country code.

`public.pos_customer_suggestions(p_pin_session_id uuid, p_query text,
p_by_phone boolean)` returns a JSON array of up to five objects with `name`
and `phone`. There is no client-supplied branch. The RPC resolves it from the
active employee PIN and current paired POS device bound to the authenticated
principal. The cashier, manager and owner POS roles can search their active
branch. The client discards suggestions on a session or pairing change and
does not persist the directory on the till.

The migration is `20261126170723_bizbot_pos_branch_customer_suggestions_001.sql`.
It adds the private table, two branch-first indexes, the bounded read and an
accepted-order trigger. Install the contract before deploying a client that
needs suggestions. No payment or sync RPC is redefined.
