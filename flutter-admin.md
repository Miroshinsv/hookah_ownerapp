Промт для Flutter-мобильного приложения

Разработай мобильное приложение Flutter для управления сетью кальянных заведений.                                                                                        
Приложение является мобильной версией веб-админки.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
BACKEND                                                                                                                                                                  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

API: GraphQL (POST /graphql, заголовок Authorization: Bearer <token>)                                                                                                    
WebSocket: /graphql/subscribe, протокол graphql-transport-ws
Аутентификация: JWT-токен, хранить в SharedPreferences

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
РОЛИ И ДОСТУП                                                                                                                                                            
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- admin   — полный доступ ко всем разделам и функциям
- owner   — управление своим заведением: заказы + персонал своей кальянной
- staff   — только просмотр заказов своей кальянной

После логина ответ содержит: { token, role, loungeId }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
GRAPHQL ОПЕРАЦИИ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Mutations:
login(userId, password) → { token role loungeId }                                                                                                                      
updateOrderStatus(orderId, status) → { id status }
deleteOrder(orderId)                                                                                                                                                   
createLounge(name, description, schedule, phone, shortAddress, fullAddress, latitude, longitude) → { id name }
updateLounge(loungeId, name, description, schedule, phone, shortAddress, fullAddress, latitude, longitude)                                                             
deleteLounge(loungeId)
setLoungeOwner(loungeId, ownerUserId)                                                                                                                                  
createStaff(userId, password, loungeId, firstName, lastName, role) → { id userId role loungeId }                                                                       
createAdmin(userId, password, firstName, lastName) → { id userId role }                                                                                                
updateStaff(staffId, firstName, lastName, role, loungeId, password?)                                                                                                   
deleteStaff(staffId)                                                                                                                                                   
sendMessage(orderId, text) → { id createdAt }

Queries:        
orders(limit: 500) → [{ id userId loungeId flavor comment phone arrivalAt status createdAt }]                                                                          
lounges → [{ id name description schedule phone rating shortAddress latitude longitude ownerUserId staff { id firstName lastName role } }]                             
staff → [{ id userId loungeId firstName lastName role rating }]
messages(orderId) → [{ id senderId senderRole text createdAt }]

Subscriptions:                                                                                                                                                           
subscription { orderStatusChanged { id status } newMessage { orderId senderId senderRole text } }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
СТРУКТУРА ДАННЫХ                                                                                                                                                         
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    subscription { orderStatusChanged { id status } newMessage { orderId senderId senderRole text } }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
СТРУКТУРА ДАННЫХ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Order.status: new | in_progress | completed | canceled
Переходы статусов: new → [in_progress, canceled], in_progress → [completed, canceled]

Staff.role: hookah_master | hostess | waiter | owner | admin
Роли для создания сотрудниками (owner): hookah_master, hostess, waiter
Роли для admin: hookah_master, hostess, waiter, owner, admin

schedule — JSON строка формата:
{ "mon": "12:00-23:00", "tue": "12:00-23:00", "sat": "14:00-02:00" }
(только открытые дни)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ЭКРАНЫ И ФУНКЦИОНАЛЬНОСТЬ                                                                                                                                                
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ЭКРАН ВХОДА
  - Поля: userId (логин), password
  - Кнопка «Войти»
  - Сохранить токен и роль в SharedPreferences, автологин при запуске

2. ДАШБОРД (главный экран)
  - Карточки-счётчики: Новые / В работе / Завершены / Отменены
  - Список последних 20 заказов с цветовой индикацией статуса
  - Кнопка ручного обновления
  - Real-time: при новом заказе (WebSocket) — push-уведомление / вибрация

3. ЗАКАЗЫ
  - Список всех заказов с пагинацией (25 на страницу)
  - Сортировка: new → in_progress → completed → canceled, внутри по дате (новые выше)
  - Карточка заказа: ID, кальянная, флавор, комментарий, телефон, время прихода, статус, дата создания
  - Кнопки смены статуса (в зависимости от текущего): «В работу», «Завершить», «Отменить»
  - Кнопка удаления заказа (с диалогом подтверждения, только admin)
  - Кнопка открытия чата по заказу (иконка с badge непрочитанных)
  - Real-time обновление статусов через WebSocket подписку

4. КАЛЬЯННЫЕ (только admin и owner)
  - Список заведений: название, телефон, рейтинг, краткий адрес, кол-во сотрудников
  - Просмотр детали: описание, карта (flutter_map / google_maps), расписание, список персонала
  - Создание кальянной (только admin):
    * Поля: название, описание, телефон (маска +7 ___ ___-__-__)
    * Расписание: выбор дней недели (Пн-Вс) + время открытия/закрытия для каждого
    * Адрес: поиск через Nominatim OpenStreetMap API, выбор точки на карте
    * Координаты lat/lng подставляются автоматически
  - Редактирование кальянной: те же поля + управление персоналом заведения + назначение/снятие владельца (ownerUserId)
  - Удаление кальянной (с подтверждением, только admin)

5. ПЕРСОНАЛ
  - Список всех сотрудников: имя, фамилия, роль (на русском), кальянная, userId, рейтинг
  - Создание нового пользователя:
    * Генератор пароля (10 символов, показать пользователю с кнопкой копировать)
    * Тип: admin (только admin), owner (только admin), staff (admin + owner)
    * Для staff и owner — выбор loungeId из списка
  - Редактирование: имя, фамилия, роль, кальянная, опционально новый пароль
  - Удаление сотрудника (с подтверждением)

6. ЧАТ (по заказу)
  - Открывается из карточки заказа
  - Пузыри сообщений: свои (справа, золотистый фон) / чужие (слева, тёмный фон)
  - Метаданные: роль отправителя, время
  - Поле ввода + кнопка отправки
  - Real-time: новые сообщения через WebSocket подписку
  - Счётчик непрочитанных: хранить в SharedPreferences { orderId: lastReadTimestamp }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
REAL-TIME (WebSocket)                                                                                                                                                    
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Подключаться после логина
- Протокол graphql-transport-ws: сначала отправить connection_init, потом subscribe
- Обрабатывать события:
  * orderStatusChanged { id status } — обновить заказ в локальном состоянии
  * newMessage { orderId senderId senderRole text } — обновить счётчик непрочитанных, если чат открыт — добавить сообщение
- При новом заказе со статусом new — вибрация (HapticFeedback) + звук
- Показывать статус соединения (Connected / Reconnecting / Disconnected)
- Авто-переподключение с экспоненциальной задержкой

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
СТИЛЬ И ДИЗАЙН                                                                                                                                                           
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Тёмная тема:
background:    #0a0a0a                                                                                                                                                 
surface:       #141414                                                                                                                                                 
surface2:      #1a1a1a
border:        #2a2a2a                                                                                                                                                 
gold (accent): #c9a96e
text:          #e8e8e8                                                                                                                                                 
muted:         #888888                                                                                                                                                 
blue:          #60a5fa   (статус new)                                                                                                                                  
yellow:        #fbbf24   (статус in_progress)                                                                                                                          
green:         #4ade80   (статус completed)
red:           #f87171   (статус canceled / ошибки)

Навигация: BottomNavigationBar с разделами Дашборд / Заказы / Кальянные / Персонал                                                                                       
(скрывать недоступные разделы в зависимости от роли)

Русская локализация: все лейблы, даты, сообщения на русском языке.

Статусы на русском: Новый / В работе / Завершён / Отменён                                                                                                                
Роли на русском: Кальянный мастер / Хостес / Официант / Администратор / Владелец / Посетитель

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
ТЕХНИЧЕСКИЙ СТЕК (рекомендуемый)                                                                                                                                         
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- State management: Riverpod или Bloc
- HTTP + GraphQL: graphql_flutter или gql + dio
- WebSocket: web_socket_channel
- Карта: flutter_map (OpenStreetMap) + geocoding/Nominatim
- Хранение: shared_preferences
- Маска телефона: mask_text_input_formatter
- Уведомления/вибрация: flutter_local_notifications + vibration
- Навигация: go_router

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                                                                                                                 
ДОПОЛНИТЕЛЬНЫЕ ТРЕБОВАНИЯ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Pull-to-refresh на всех списках
- Snackbar/Toast для уведомлений об успехе и ошибках
- Индикатор загрузки на кнопках действий (чтобы не дублировать нажатия)
- Пустые состояния (empty state) со значком и текстом
- Адаптация под Android и iOS
- Конфигурируемый BASE_URL через переменную окружения / dart-define

Промт охватывает весь функционал веб-админки: авторизацию, дашборд, заказы с real-time обновлениями, CRUD кальянных с картой, управление персоналом, чат и               
WebSocket-подписки. Цветовая схема и роли перенесены один в один из admin.html.                                                                                          
                                                                                
