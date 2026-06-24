const kLoginMutation = r'''
mutation Login($userId: String!, $password: String!) {
  login(userId: $userId, password: $password) {
    token
    role
    loungeId
  }
}
''';

const kOrdersQuery = r'''
query Orders($limit: Int) {
  orders(limit: $limit) {
    id
    userId
    loungeId
    flavor
    comment
    phone
    firstName
    lastName
    arrivalAt
    status
    createdAt
  }
}
''';

const kUpdateOrderStatusMutation = r'''
mutation UpdateOrderStatus($orderId: String!, $status: String!) {
  updateOrderStatus(orderId: $orderId, status: $status) {
    id
    status
  }
}
''';

const kDeleteOrderMutation = r'''
mutation DeleteOrder($orderId: String!) {
  deleteOrder(orderId: $orderId)
}
''';

const kLoungesQuery = r'''
query Lounges {
  lounges {
    id
    name
    description
    schedule
    phone
    rating
    shortAddress
    latitude
    longitude
    ownerUserId
    mediaEnabled
    mediaMaxFiles
    chatEnabled
    feedbackEnabled
    photos {
      id
      url
    }
    staff {
      id
      userId
      firstName
      lastName
      roles
    }
  }
}
''';

const kCreateLoungeMutation = r'''
mutation CreateLounge(
  $name: String!
  $description: String
  $schedule: String
  $phone: String
  $shortAddress: String
  $latitude: Float
  $longitude: Float
) {
  createLounge(
    name: $name
    description: $description
    schedule: $schedule
    phone: $phone
    shortAddress: $shortAddress
    latitude: $latitude
    longitude: $longitude
  ) {
    id
    name
  }
}
''';

const kUpdateLoungeMutation = r'''
mutation UpdateLounge(
  $loungeId: String!
  $name: String!
  $description: String
  $schedule: String
  $phone: String
  $shortAddress: String
  $latitude: Float
  $longitude: Float
) {
  updateLounge(
    loungeId: $loungeId
    name: $name
    description: $description
    schedule: $schedule
    phone: $phone
    shortAddress: $shortAddress
    latitude: $latitude
    longitude: $longitude
  ) {
    id
    name
  }
}
''';

const kDeleteLoungeMutation = r'''
mutation DeleteLounge($loungeId: String!) {
  deleteLounge(loungeId: $loungeId)
}
''';

const kSetLoungeOwnerMutation = r'''
mutation SetLoungeOwner($loungeId: String!, $ownerUserId: String!) {
  setLoungeOwner(loungeId: $loungeId, ownerUserId: $ownerUserId) {
    id
  }
}
''';

const kStaffQuery = r'''
query Staff {
  staff {
    id
    userId
    loungeId
    loungeIds
    firstName
    lastName
    roles
    rating
    photoUrl
  }
}
''';

const kStaffProfileQuery = r'''
query StaffProfile($staffId: String!) {
  staffProfile(staffId: $staffId) {
    id
    userId
    firstName
    lastName
    bio
    photoUrl
    roles
    rating
    lounges {
      loungeId
      name
      shortAddress
      schedule
    }
  }
}
''';

const kStaffScheduleQuery = r'''
query StaffSchedule($staffId: String!, $loungeId: String!, $month: String!) {
  staffSchedule(staffId: $staffId, loungeId: $loungeId, month: $month) {
    staffId
    loungeId
    month
    schedule
  }
}
''';

const kUploadStaffPhotoMutation = r'''
mutation UploadStaffPhoto($staffId: String!, $imageBase64: String!, $mimeType: String!) {
  uploadStaffPhoto(staffId: $staffId, imageBase64: $imageBase64, mimeType: $mimeType)
}
''';

const kCreateStaffMutation = r'''
mutation CreateStaff(
  $userId: String!
  $password: String!
  $loungeIds: [ID]!
  $firstName: String
  $lastName: String
  $roles: [String]!
) {
  createStaff(
    userId: $userId
    password: $password
    loungeIds: $loungeIds
    firstName: $firstName
    lastName: $lastName
    roles: $roles
  ) {
    id
    userId
    roles
    loungeId
    loungeIds
  }
}
''';

const kCreateAdminMutation = r'''
mutation CreateAdmin(
  $userId: String!
  $password: String!
  $firstName: String
  $lastName: String
) {
  createAdmin(
    userId: $userId
    password: $password
    firstName: $firstName
    lastName: $lastName
  ) {
    id
    userId
    roles
  }
}
''';

const kUpdateStaffMutation = r'''
mutation UpdateStaff(
  $staffId: String!
  $firstName: String
  $lastName: String
  $roles: [String]
  $loungeIds: [ID]
  $password: String
) {
  updateStaff(
    staffId: $staffId
    firstName: $firstName
    lastName: $lastName
    roles: $roles
    loungeIds: $loungeIds
    password: $password
  ) {
    id
    userId
    firstName
    lastName
    roles
    loungeId
    loungeIds
    rating
  }
}
''';

const kDeleteStaffMutation = r'''
mutation DeleteStaff($staffId: String!) {
  deleteStaff(staffId: $staffId)
}
''';

const kSetStaffScheduleMutation = r'''
mutation SetStaffSchedule($staffId: String!, $loungeId: String!, $month: String!, $schedule: String!) {
  setStaffSchedule(staffId: $staffId, loungeId: $loungeId, month: $month, schedule: $schedule) {
    staffId
    loungeId
    month
    schedule
  }
}
''';

const kMessagesQuery = r'''
query Messages($orderId: String!) {
  messages(orderId: $orderId) {
    id
    senderId
    senderRole
    text
    createdAt
  }
}
''';

const kSendMessageMutation = r'''
mutation SendMessage($orderId: String!, $text: String!) {
  sendMessage(orderId: $orderId, text: $text) {
    id
    createdAt
  }
}
''';

const kOrderStatusChangedSubscription = r'''
subscription OrderStatusChanged {
  orderStatusChanged {
    id
    status
  }
}
''';

const kNewMessageSubscription = r'''
subscription NewMessage {
  newMessage {
    orderId
    senderId
    senderRole
    text
  }
}
''';

const kSetLoungeMediaEnabledMutation = r'''
mutation SetLoungeMediaEnabled($loungeId: String!, $mediaEnabled: Boolean!) {
  setLoungeMediaEnabled(loungeId: $loungeId, mediaEnabled: $mediaEnabled)
}
''';

const kSetLoungeMediaMaxFilesMutation = r'''
mutation SetLoungeMediaMaxFiles($loungeId: String!, $mediaMaxFiles: Int!) {
  setLoungeMediaMaxFiles(loungeId: $loungeId, mediaMaxFiles: $mediaMaxFiles)
}
''';

const kUploadLoungePhotoMutation = r'''
mutation UploadLoungePhoto($loungeId: String!, $imageBase64: String!, $mimeType: String!) {
  uploadLoungePhoto(loungeId: $loungeId, imageBase64: $imageBase64, mimeType: $mimeType)
}
''';

const kDeleteLoungePhotoMutation = r'''
mutation DeleteLoungePhoto($loungeId: String!, $photoId: String!) {
  deleteLoungePhoto(loungeId: $loungeId, photoId: $photoId)
}
''';

const kSetChatEnabledMutation = r'''
mutation SetChatEnabled($loungeId: String!, $chatEnabled: Boolean!) {
  setChatEnabled(loungeId: $loungeId, chatEnabled: $chatEnabled)
}
''';

const kLoungeChatMessagesQuery = r'''
query LoungeChatMessages($loungeId: String!, $limit: Int) {
  loungeChatMessages(loungeId: $loungeId, limit: $limit) {
    messageId
    loungeId
    senderId
    senderRole
    text
    createdAt
  }
}
''';

const kSendLoungeChatMessageMutation = r'''
mutation SendLoungeChatMessage($loungeId: String!, $text: String!) {
  sendLoungeChatMessage(loungeId: $loungeId, text: $text) {
    messageId
    createdAt
  }
}
''';

const kNewLoungeChatMessageSubscription = r'''
subscription NewLoungeChatMessage($loungeId: String!) {
  newLoungeChatMessage(loungeId: $loungeId) {
    messageId
    loungeId
    senderId
    senderRole
    text
    createdAt
  }
}
''';

/// Все оценки без фильтрации — используется на дашборде.
/// Переменные соответствуют тому, что реально передаётся в variables dict,
/// иначе gql-сериализатор вырезает «лишние» объявления из сигнатуры операции.
const kAllRatingsQuery = r'''
query AllRatings($limit: Int) {
  allRatings(limit: $limit) {
    ratingId
    userId
    targetType
    targetId
    score
    createdAt
  }
}
''';

/// Оценки с фильтром по объекту — используется на экране кальянной / сотрудника.
const kFilteredRatingsQuery = r'''
query FilteredRatings($limit: Int, $targetType: String, $targetId: String) {
  allRatings(limit: $limit, targetType: $targetType, targetId: $targetId) {
    ratingId
    userId
    targetType
    targetId
    score
    createdAt
  }
}
''';

const kRatingStatsQuery = r'''
query RatingStats($targetType: String!, $targetId: String!) {
  ratingStats(targetType: $targetType, targetId: $targetId) {
    avgRating
    count
  }
}
''';

const kLoungeFeedbacksQuery = r'''
query LoungeFeedbacks($loungeId: String!, $limit: Int) {
  loungeFeedbacks(loungeId: $loungeId, limit: $limit) {
    feedbackId
    score
    createdAt
    userId
    orderId
    comment
  }
}
''';

const kIsNotesEnabledQuery = r'''
query IsNotesEnabled($loungeId: String!) {
  isNotesEnabled(loungeId: $loungeId)
}
''';

const kCreateNoteMutation = r'''
mutation CreateNote($loungeId: String!, $entityType: String!, $entityId: String!, $text: String!) {
  createNote(loungeId: $loungeId, entityType: $entityType, entityId: $entityId, text: $text) {
    noteId
    authorName
    text
    createdAt
  }
}
''';

const kDeleteNoteMutation = r'''
mutation DeleteNote($noteId: String!, $loungeId: String!) {
  deleteNote(noteId: $noteId, loungeId: $loungeId)
}
''';

const kLoungeEntityNotesQuery = r'''
query LoungeEntityNotes($loungeId: String!, $limit: Int) {
  notes(loungeId: $loungeId, entityType: "lounge", entityId: $loungeId, limit: $limit) {
    items {
      noteId
      authorName
      text
      createdAt
    }
    total
  }
}
''';

const kUserNotesQuery = r'''
query UserNotes($loungeId: String!, $userId: String!, $limit: Int) {
  notes(loungeId: $loungeId, entityType: "user", entityId: $userId, limit: $limit) {
    items {
      noteId
      authorName
      text
      createdAt
    }
    total
  }
}
''';

const kLoungeNotesQuery = r'''
query LoungeNotes($loungeId: String!, $limit: Int) {
  notes(loungeId: $loungeId, limit: $limit) {
    items {
      noteId
      createdAt
    }
    total
  }
}
''';

const kRegisterDeviceMutation = r'''
mutation RegisterDevice($fcmToken: String!) {
  registerDevice(fcmToken: $fcmToken)
}
''';

const kUnregisterDeviceMutation = r'''
mutation UnregisterDevice($fcmToken: String!) {
  unregisterDevice(fcmToken: $fcmToken)
}
''';

const kRequestFeedbackMutation = r'''
mutation RequestOrderFeedback($orderId: String!) {
  requestOrderFeedback(orderId: $orderId)
}
''';

const kFeedbackRequestQuery = r'''
query FeedbackRequest($orderId: String!) {
  feedbackRequest(orderId: $orderId) {
    status
  }
}
''';

