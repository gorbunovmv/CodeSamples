Есть задача создать небольшую транзакционную систему с сущностями "Клиенты", "Карты", "Транзакции".
Клиент владеет одной или несколькими картами, по карте может совершаться одна или более транзакций (операций).
Необходимо спроектировать модель БД (желательно в третьей нормальной форме) и наполнить ее данными (сгенерировать данные), при необходимости создать индексы.
Входными параметрами этой процедуры должны быть "кол-во клиентов" (количество клиентов, которое генерим), "кол-во карт" (количество карт, которое генерим), 
"кол-во транзакций" (количество операций, которое генерим)
Требования:
Для каждой сущности должен быть создан первичный ключ.
Для клиента должно быть сгенерировано ФИО (либо просто фамилия). Можно не морочиться с реальными ФИО - просто любой набор букв
Для карты должен быть сгенерирован номер карты (ЛЮБЫЕ 16 цифр) и дата окончания действия карты (Дата)
Для транзакций обязательными полями являются сумма, тип операции (пополнение, снятие) и дата/время.  Вместо типа операции можно использовать знак плюс или минус у суммы операции
В случае , если после очередной транзакции по карте баланс уходит в минус (то есть суммы предыдущих пополнений не хватает для очередной покупки) , то такую транзакцию не вставляем, 
выводим сообщение (либо записываем куда-нибудь) "недостаточно средств",
В случае совершения операции после даты окончания действия карты - такую транзакцию тоже не вставляем, выводим сообщение - "карта недействительна"

The task is to develop a small transactioning system with "Clients", "Cards" and "Transactions" entities.
The client has one or several cards, one or more transactions can be made on the card.
It is necessary to design DB model (the third normal form is preffered) and fill it by data (generate data), create indexes if necessary.
Input parameters of that procedure should be "quantity of customers" (a customers quantity, that will be generated), "quantity of cards" (a cards quantity, 
that will be generated),
"quantity of transactions" (an operations quantity, that will be generated).
Requirements:
The primary key should be create for every entity.
A full name should be generated for client (or just last name), there is no need to make real full name, just any sequence of letters.
A card number should be generated for card (any 16 digits) and card expiration date (Date).
For transactions, the required fields are amount, operation type (replenishment, purchase/withdrawal) and date/time. It is possible to use "plus" or "minus" sign with amount 
instead of operation type.
In case when after the regular transaction a card balance becomes negative (that is the amount of previous deposits is not enough for next purchase), 
so that transaction shouldn't be inserted, print message(or save somewhere) "insufficient funds".
In case producing of operation after card expiration date - that transaction should't be inserted too, print message - "the card is not valid".