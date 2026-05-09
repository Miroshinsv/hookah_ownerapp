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
  }
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
