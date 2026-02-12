The task is to develop a small transactioning system with "Clients", "Cards" and "Transactions" entities.
The client has one or several cards, one or more transactions can be made on the card.
It is necessary to design DB model (the third normal form is preffered) and fill it (generate) by data, create indexes if necessary.
Input parameters of that procedure should be "quantity of customers" (a customers quantity, that will be generated), "quantity of cards" (a cards quantity, 
that will be generated),"quantity of transactions" (an operations quantity, that will be generated).
Requirements:
The primary key should be create for every entity.
A full name should be generated for client (or just last name), there is no need to make real full name, just any sequence of letters.
A card number should be generated for card (any 16 digits) and card expiration date (Date).
For transactions, the mandatory fields are amount, operation type (replenishment, withdrawal) and date/time. It is possible to use "plus" or "minus" sign with amount 
instead of operation type.
In case when if the regular transaction becomes a card balance negative (that is the amount of previous deposits is not enough for next purchase), 
so that transaction shouldn't be inserted, print message(or save somewhere) "insufficient funds".
In case producing of operation after card expiration date - that transaction should't be inserted too, print message - "the card is not valid".